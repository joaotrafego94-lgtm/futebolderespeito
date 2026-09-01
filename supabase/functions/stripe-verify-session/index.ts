// Confere no Stripe se uma sessão de pagamento foi paga de verdade,
// e só então grava o pagamento no banco. É esta função que decide,
// não a tela: ninguém entra na lista, nem fica pendente, só por
// dizer que pagou.
//
// Dois casos, conforme o metadata que a stripe-create-session gravou:
//
//   metadata.player_id                       -- vaga já existia
//     (alguém pagando por quem foi adicionado sem celular). Só
//     confirma o paid=true nessa vaga.
//   metadata.name / game_date / token        -- entrada nova. A vaga
//     só é criada AGORA, já paga -- se a pessoa tivesse desistido no
//     meio do pagamento, nunca teria chegado a existir.
//
// Mesmo secret da stripe-create-session:
//   STRIPE_SECRET_KEY
//
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente
// no ambiente de toda Edge Function -- não precisa configurar.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !STRIPE_SECRET_KEY) {
    return json({ error: "Faltam secrets configurados nesta função" }, 500);
  }

  let body: { session_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Corpo inválido" }, 400);
  }
  const sessionId = body.session_id;
  if (!sessionId) return json({ error: "session_id é obrigatório" }, 400);

  const stripeRes = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}`, {
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
  });
  const session = await stripeRes.json();
  if (!stripeRes.ok) {
    console.error("Stripe recusou consultar a sessão:", session);
    return json({ error: "Sessão não encontrada no Stripe" }, 404);
  }

  if (session.payment_status !== "paid") {
    return json({ ok: false, motivo: "Pagamento ainda não confirmado pelo Stripe" });
  }

  const dbHeaders = { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };
  const meta = session.metadata || {};

  // Caso 1: vaga já existia (alguém pagando por quem foi adicionado
  // sem celular). where=paid=eq.false: idempotente, não sobrescreve
  // se já tiver sido confirmado antes.
  if (meta.player_id) {
    const updateRes = await fetch(
      `${SUPABASE_URL}/rest/v1/players?id=eq.${meta.player_id}&paid=eq.false`,
      {
        method: "PATCH",
        headers: { ...dbHeaders, "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify({ paid: true, paid_at: new Date().toISOString() }),
      }
    );
    if (!updateRes.ok) {
      console.error("Falhou marcar paid=true:", await updateRes.text());
      return json({ error: "Pagamento confirmado no Stripe, mas não deu pra salvar no banco" }, 500);
    }
    return json({ ok: true, player_id: meta.player_id });
  }

  // Caso 2: entrada nova. A vaga só passa a existir agora.
  const name = meta.name;
  const gameDate = meta.game_date;
  const token = meta.token;
  if (!name || !gameDate || !token) return json({ error: "Sessão sem dados do jogador" }, 400);

  // Idempotente: se esta sessão já tiver sido confirmada antes (ex.: a
  // pessoa recarregou a página de volta), não cria uma vaga duplicada
  // nem soma o mês duas vezes.
  const claimRes = await fetch(
    `${SUPABASE_URL}/rest/v1/player_claims?token=eq.${token}&select=player_id`,
    { headers: dbHeaders }
  );
  const claims = await claimRes.json();
  if (claims && claims[0]) return json({ ok: true, player_id: claims[0].player_id, name });

  const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/players`, {
    method: "POST",
    headers: { ...dbHeaders, "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify({ game_date: gameDate, name, paid: true, paid_at: new Date().toISOString(), source: "avulso" }),
  });
  const inserted = await insertRes.json();
  const player = inserted && inserted[0];
  if (!insertRes.ok || !player) {
    console.error("Falhou criar jogador pago:", inserted);
    return json({ error: "Pagamento confirmado no Stripe, mas não deu pra salvar no banco" }, 500);
  }

  // Guarda o token pra idempotência e pra essa pessoa poder sair da
  // própria vaga depois (mesmo mecanismo do join_game).
  await fetch(`${SUPABASE_URL}/rest/v1/player_claims`, {
    method: "POST",
    headers: { ...dbHeaders, "Content-Type": "application/json" },
    body: JSON.stringify({ player_id: player.id, token }),
  });

  return json({ ok: true, player_id: player.id, name });
});
