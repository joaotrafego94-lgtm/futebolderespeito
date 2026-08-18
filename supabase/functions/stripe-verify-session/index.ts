// Confere no Stripe se uma sessão de pagamento foi paga de verdade,
// e só então marca o jogador como pago no banco. É esta função que
// substitui o clique manual do organizador -- ninguém entra na lista
// "de graça" só por dizer que pagou; o Stripe é quem confirma.
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

  // Pergunta ao Stripe -- nunca confia no que o navegador diz sobre
  // si mesmo. É este fetch que é a fonte da verdade.
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

  const playerId = session.client_reference_id;
  if (!playerId) return json({ error: "Sessão sem jogador associado" }, 400);

  // where=eq.false: idempotente -- se já estava pago (ex.: a pessoa
  // recarregou a página), não sobrescreve o paid_at original.
  const updateRes = await fetch(
    `${SUPABASE_URL}/rest/v1/players?id=eq.${playerId}&paid=eq.false`,
    {
      method: "PATCH",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({ paid: true, paid_at: new Date().toISOString() }),
    }
  );
  if (!updateRes.ok) {
    console.error("Falhou marcar paid=true:", await updateRes.text());
    return json({ error: "Pagamento confirmado no Stripe, mas não deu pra salvar no banco" }, 500);
  }

  return json({ ok: true });
});
