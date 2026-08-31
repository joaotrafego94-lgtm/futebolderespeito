// O Stripe chama isto SOZINHO, direto do servidor dele, assim que um
// pagamento é aprovado -- não depende de a pessoa voltar pro site
// nem de ela deixar o navegador aberto. É a rede de segurança que
// falta na stripe-verify-session: se alguém pagar e fechar a aba
// antes do redirecionamento automático, é este webhook que garante
// que a vaga vira paga mesmo assim.
//
// A mesma lógica de gravar no banco já existe na stripe-verify-session
// (que continua a dar a confirmação instantânea pra quem espera na
// tela) -- as duas são seguras de rodar pro mesmo pagamento, uma não
// atrapalha a outra: a segunda a chegar não faz nada, porque o dado
// já está gravado (paid=eq.false na atualização, e o token já visto
// na criação).
//
// Precisa de DOIS secrets configurados nesta função:
//   STRIPE_SECRET_KEY     -- a mesma chave das outras duas funções
//   STRIPE_WEBHOOK_SECRET -- gerado pelo Stripe ao criar o endpoint
//                            do webhook (ver instruções no README)
//
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já vêm automáticos.

async function assinaturaValida(payload: string, header: string, secret: string): Promise<boolean> {
  const partes = Object.fromEntries(header.split(",").map((p) => p.split("=")));
  const timestamp = partes["t"];
  const assinaturaRecebida = partes["v1"];
  if (!timestamp || !assinaturaRecebida) return false;

  // Recusa eventos com mais de 5 minutos -- evita reenvio de uma
  // assinatura antiga capturada por alguém.
  const idadeSegundos = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (idadeSegundos > 300) return false;

  const chave = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const assinado = await crypto.subtle.sign(
    "HMAC",
    chave,
    new TextEncoder().encode(`${timestamp}.${payload}`)
  );
  const calculada = Array.from(new Uint8Array(assinado))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return calculada === assinaturaRecebida;
}

function addOneMonth(isoDate: string): string {
  const d = new Date(isoDate + "T00:00:00Z");
  d.setUTCMonth(d.getUTCMonth() + 1);
  return d.toISOString().slice(0, 10);
}

// Mesma lógica de supabase/functions/stripe-verify-session/index.ts —
// duplicada de propósito, as duas funções são coladas independentes
// no painel do Supabase, sem import compartilhado entre elas.
async function confirmarMensalista(
  SUPABASE_URL: string,
  dbHeaders: Record<string, string>,
  name: string,
  gameDate: string,
  token: string
) {
  const hoje = new Date().toISOString().slice(0, 10);

  const memberRes = await fetch(
    `${SUPABASE_URL}/rest/v1/members?token=eq.${token}&select=id,valid_until`,
    { headers: dbHeaders }
  );
  const members = await memberRes.json();
  const existing = members && members[0];
  const base = existing && existing.valid_until > hoje ? existing.valid_until : hoje;
  const validUntil = addOneMonth(base);

  if (existing) {
    await fetch(`${SUPABASE_URL}/rest/v1/members?id=eq.${existing.id}`, {
      method: "PATCH",
      headers: { ...dbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ valid_until: validUntil, updated_at: new Date().toISOString() }),
    });
  } else {
    await fetch(`${SUPABASE_URL}/rest/v1/members`, {
      method: "POST",
      headers: { ...dbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ name, token, valid_until: validUntil }),
    });
  }

  const weekKey = name.trim().toLowerCase();
  const weekRes = await fetch(
    `${SUPABASE_URL}/rest/v1/players?game_date=eq.${gameDate}&select=id,name,paid`,
    { headers: dbHeaders }
  );
  const week = await weekRes.json();
  let player = (week || []).find((p: any) => p.name.trim().toLowerCase() === weekKey);

  if (player && !player.paid) {
    await fetch(`${SUPABASE_URL}/rest/v1/players?id=eq.${player.id}`, {
      method: "PATCH",
      headers: { ...dbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ paid: true, paid_at: new Date().toISOString(), source: "mensalista" }),
    });
  } else if (!player) {
    const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/players`, {
      method: "POST",
      headers: { ...dbHeaders, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ game_date: gameDate, name, paid: true, paid_at: new Date().toISOString(), source: "mensalista" }),
    });
    const inserted = await insertRes.json();
    player = inserted && inserted[0];
  }

  if (player) {
    await fetch(`${SUPABASE_URL}/rest/v1/player_claims`, {
      method: "POST",
      headers: { ...dbHeaders, "Content-Type": "application/json", Prefer: "resolution=ignore-duplicates" },
      body: JSON.stringify({ player_id: player.id, token }),
    });
  }

  return player;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Método não permitido", { status: 405 });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !WEBHOOK_SECRET) {
    return new Response("Faltam secrets configurados nesta função", { status: 500 });
  }

  const rawBody = await req.text();
  const sigHeader = req.headers.get("stripe-signature");
  if (!sigHeader || !(await assinaturaValida(rawBody, sigHeader, WEBHOOK_SECRET))) {
    console.error("Assinatura do webhook não bateu -- requisição recusada.");
    return new Response("Assinatura inválida", { status: 400 });
  }

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response("Corpo inválido", { status: 400 });
  }

  // Só nos interessa o momento em que o pagamento é confirmado.
  if (event.type !== "checkout.session.completed") {
    return new Response("ok (evento ignorado)", { status: 200 });
  }

  const session = event.data?.object;
  if (!session || session.payment_status !== "paid") {
    return new Response("ok (ainda não pago)", { status: 200 });
  }

  const dbHeaders = { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };
  const meta = session.metadata || {};

  // Caso 1: vaga já existia (alguém pagando por quem foi adicionado
  // sem celular). where=paid=eq.false: idempotente.
  if (meta.player_id) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/players?id=eq.${meta.player_id}&paid=eq.false`, {
      method: "PATCH",
      headers: { ...dbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ paid: true, paid_at: new Date().toISOString() }),
    });
    if (!r.ok) console.error("Webhook: falhou marcar paid=true:", await r.text());
    return new Response("ok", { status: 200 });
  }

  // Caso 2: entrada nova. Só existe a partir de agora.
  const name = meta.name;
  const gameDate = meta.game_date;
  const token = meta.token;
  if (!name || !gameDate || !token) return new Response("ok (sessão sem dados do jogador)", { status: 200 });

  const claimRes = await fetch(
    `${SUPABASE_URL}/rest/v1/player_claims?token=eq.${token}&select=player_id`,
    { headers: dbHeaders }
  );
  const claims = await claimRes.json();
  if (claims && claims[0]) return new Response("ok (já processado)", { status: 200 });

  if (meta.plan === "mensal") {
    const player = await confirmarMensalista(SUPABASE_URL, dbHeaders, name, gameDate, token);
    if (!player) console.error("Webhook: falhou confirmar mensalista");
    return new Response("ok", { status: 200 });
  }

  const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/players`, {
    method: "POST",
    headers: { ...dbHeaders, "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify({ game_date: gameDate, name, paid: true, paid_at: new Date().toISOString(), source: "avulso" }),
  });
  const inserted = await insertRes.json();
  const player = inserted && inserted[0];
  if (!insertRes.ok || !player) {
    console.error("Webhook: falhou criar jogador pago:", inserted);
    return new Response("ok (erro ao salvar)", { status: 200 });
  }

  await fetch(`${SUPABASE_URL}/rest/v1/player_claims`, {
    method: "POST",
    headers: { ...dbHeaders, "Content-Type": "application/json" },
    body: JSON.stringify({ player_id: player.id, token }),
  });

  return new Response("ok", { status: 200 });
});
