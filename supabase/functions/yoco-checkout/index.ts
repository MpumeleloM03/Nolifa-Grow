// Starts a Yoco card payment for the signed-in person: a membership ({}) or an
// order ({"orderId": ...}). The price comes from the server, never from the phone.
import { createClient } from 'npm:@supabase/supabase-js@2';

const PRICE_CENTS: Record<string, number> = { member: 3000_00, max: 7000_00 };
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const key = Deno.env.get('YOCO_SECRET_KEY');
  if (!key) return json({ error: 'Payments are not switched on yet.' }, 503);
  const url = Deno.env.get('SUPABASE_URL')!;
  const auth = req.headers.get('Authorization') ?? '';
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
  const { data: u } = await asUser.auth.getUser();
  if (!u?.user) return json({ error: 'Sign in first.' }, 401);
  const uid = u.user.id;

  const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const body0 = await req.json().catch(() => ({}));
  const orderId: string | undefined = typeof body0?.orderId === 'string' ? body0.orderId : undefined;

  let amount: number;
  let tier: string;
  let kind: 'membership' | 'order';
  if (orderId) {
    // An order: the price is the order's own total on the server.
    const { data: o } = await db.from('market_orders').select('id,customer_id,data').eq('id', orderId).maybeSingle();
    if (!o || o.customer_id !== uid) return json({ error: 'That is not your order.' }, 403);
    if (o.data?.paid === true) return json({ error: 'This order is already paid.' }, 409);
    if (o.data?.method === 'cash') return json({ error: 'Cash on delivery needs no card.' }, 409);
    const { data: cents } = await db.rpc('order_amount_cents', { p_id: orderId });
    if (!cents || cents < 500) return json({ error: 'That order has no amount to pay.' }, 400);
    amount = cents as number;
    tier = 'order';
    kind = 'order';
  } else {
    const { data: m } = await db.from('memberships').select('tier,status').eq('uid', uid).maybeSingle();
    if (!m || m.status !== 'awaiting_payment') return json({ error: 'There is no membership waiting for payment. Join first.' }, 409);
    amount = PRICE_CENTS[m.tier];
    if (!amount) return json({ error: 'Unknown plan.' }, 400);
    tier = m.tier;
    kind = 'membership';
  }

  const { data: pay, error: pe } = await db.from('payments').insert({ uid, tier, kind, amount_cents: amount, order_id: orderId ?? null }).select('id').single();
  if (pe) return json({ error: 'Could not start the payment.' }, 500);

  const site = Deno.env.get('RETURN_URL') ?? 'https://nolifa-backoffice.web.app/paid.html';
  const res = await fetch('https://payments.yoco.com/api/checkouts', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount,
      currency: 'ZAR',
      successUrl: `${site}?ok=1&for=${kind}`,
      cancelUrl: `${site}?cancelled=1`,
      failureUrl: `${site}?failed=1`,
      clientReferenceId: pay.id,
      metadata: { paymentId: pay.id, uid, tier, kind, orderId: orderId ?? '' },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.redirectUrl) {
    await db.from('payments').update({ status: 'failed' }).eq('id', pay.id);
    return json({ error: 'The card service did not answer. Try again in a moment.' }, 502);
  }
  await db.from('payments').update({ checkout_id: body.id, processing_mode: body.processingMode ?? null }).eq('id', pay.id);
  return json({ url: body.redirectUrl, mode: body.processingMode ?? null, amount });
});
