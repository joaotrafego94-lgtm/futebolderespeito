// Cria uma sessão de pagamento no Stripe pro jogador que acabou de
// entrar na lista. O preço vem SEMPRE do banco (nunca do navegador),
// pra ninguém conseguir adulterar o valor mandando um número diferente
// na requisição.
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

  let body: { player_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Corpo inválido" }, 400);
  }
  const playerId = body.player_id;
  if (!playerId) return json({ error: "player_id é obrigatório" }, 400);

  // Busca o jogador e o jogo dele direto no banco, com a chave de
  // serviço (ignora RLS de propósito -- esta função É a autoridade).
  const playerRes = await fetch(
    `${SUPABASE_URL}/rest/v1/players?id=eq.${playerId}&select=id,name,paid,game_date`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } }
  );
  const players = await playerRes.json();
  const player = players && players[0];
  if (!player) return json({ error: "Jogador não encontrado" }, 404);
  if (player.paid) return json({ error: "Esse jogador já está marcado como pago" }, 400);

  const gameRes = await fetch(
    `${SUPABASE_URL}/rest/v1/games?game_date=eq.${player.game_date}&select=game_date,price`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } }
  );
  const games = await gameRes.json();
  const game = games && games[0];
  if (!game) return json({ error: "Jogo não encontrado" }, 404);

  const price = Number(game.price || 0);
  if (price <= 0) return json({ error: "Esse jogo não tem valor definido" }, 400);

  // success_url/cancel_url apontam pro mesmo site que chamou esta
  // função -- funciona tanto em produção quanto testando localmente.
  const origin = req.headers.get("origin") || "https://futebolderespeito.vercel.app";
  const successUrl = `${origin}/?session_id={CHECKOUT_SESSION_ID}`;
  const cancelUrl = `${origin}/`;

  const params = new URLSearchParams();
  params.set("mode", "payment");
  params.set("client_reference_id", playerId);
  params.set("success_url", successUrl);
  params.set("cancel_url", cancelUrl);
  params.set("automatic_payment_methods[enabled]", "true");
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "eur");
  params.set("line_items[0][price_data][unit_amount]", String(Math.round(price * 100)));
  params.set("line_items[0][price_data][product_data][name]", "Futebol de Respeito");
  params.set(
    "line_items[0][price_data][product_data][description]",
    `Pelada de ${game.game_date} — ${player.name}`
  );

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
