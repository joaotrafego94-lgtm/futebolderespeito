// Cria uma sessão de pagamento no Stripe. Dois modos:
//
//   { player_id }              -- alguém já está pendente na lista
//                                 (ex.: foi adicionado por um amigo sem
//                                 celular) e quer pagar agora.
//   { name, game_date, token } -- entrada nova. NÃO cria a vaga aqui --
//                                 só depois que o Stripe confirmar que
//                                 pagou (stripe-verify-session). Assim,
//                                 quem desiste no meio do pagamento não
//                                 deixa um nome fantasma em "Aguardando
//                                 pagamento" pra sempre.
//
// Só existe pra pagamento avulso -- mensalista paga por transferência
// pro IBAN e o organizador confirma na mão (ver index.html).
//
// O preço vem SEMPRE do banco (nunca do navegador), pra ninguém
// conseguir adulterar o valor mandando um número diferente na requisição.
//
// Precisa de UM secret configurado nesta função, no painel do
// Supabase (Edge Functions -> stripe-create-session -> Secrets):
//   STRIPE_SECRET_KEY -- chave secreta do Stripe (sk_...)
//
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente
// no ambiente de toda Edge Function -- o Supabase nem deixa criar um
// secret com esses nomes, é reservado. Não precisa configurar.

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

  let body: { player_id?: string; name?: string; game_date?: string; token?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Corpo inválido" }, 400);
  }

  const dbHeaders = { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };

  let gameDate: string;
  let metadata: Record<string, string>;
  let description: string;

  if (body.player_id) {
    const playerRes = await fetch(
      `${SUPABASE_URL}/rest/v1/players?id=eq.${body.player_id}&select=id,name,paid,game_date`,
      { headers: dbHeaders }
    );
    const players = await playerRes.json();
    const player = players && players[0];
    if (!player) return json({ error: "Jogador não encontrado" }, 404);
    if (player.paid) return json({ error: "Esse jogador já está marcado como pago" }, 400);
    gameDate = player.game_date;
    metadata = { player_id: body.player_id };
    description = `Pelada de ${gameDate} — ${player.name}`;
  } else {
    const name = (body.name || "").trim();
    if (!name || name.length > 60) return json({ error: "Nome inválido" }, 400);
    if (!body.game_date) return json({ error: "game_date é obrigatório" }, 400);
    if (!body.token) return json({ error: "token é obrigatório" }, 400);
    gameDate = body.game_date;
    metadata = { name, game_date: gameDate, token: body.token };
    description = `Pelada de ${gameDate} — ${name}`;
  }

  const gameRes = await fetch(
    `${SUPABASE_URL}/rest/v1/games?game_date=eq.${gameDate}&select=game_date,price`,
    { headers: dbHeaders }
  );
  const games = await gameRes.json();
  const game = games && games[0];
  if (!game) return json({ error: "Jogo não encontrado" }, 404);

  const price = Number(game.price || 0);
  if (price <= 0) return json({ error: "Esse jogo não tem valor definido" }, 400);

  const origin = req.headers.get("origin") || "https://futebolderespeito.vercel.app";
  const params = new URLSearchParams();
  params.set("mode", "payment");
  params.set("success_url", `${origin}/?session_id={CHECKOUT_SESSION_ID}`);
  params.set("cancel_url", `${origin}/`);
  for (const [k, v] of Object.entries(metadata)) params.set(`metadata[${k}]`, v);
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "eur");
  params.set("line_items[0][price_data][unit_amount]", String(Math.round(price * 100)));
  params.set("line_items[0][price_data][product_data][name]", "Futebol de Respeito");
  params.set("line_items[0][price_data][product_data][description]", description);

  const stripeRes = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  const session = await stripeRes.json();
  if (!stripeRes.ok) {
    console.error("Stripe recusou criar a sessão:", session);
    return json({ error: session.error?.message || "Stripe recusou o pedido" }, 502);
  }

  return json({ url: session.url });
});
