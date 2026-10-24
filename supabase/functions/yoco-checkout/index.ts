// Starts a Yoco card payment for the signed-in person's membership. The price
// comes from the plan on the server, never from the phone.
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
  const { data: m } = await db.from('memberships').select('tier,status').eq('uid', uid).maybeSingle();
  if (!m || m.status !== 'awaiting_payment') return json({ error: 'There is no membership waiting for payment. Join first.' }, 409);
  const amount = PRICE_CENTS[m.tier];
  if (!amount) return json({ error: 'Unknown plan.' }, 400);

  const { data: pay, error: pe } = await db.from('payments').insert({ uid, tier: m.tier, amount_cents: amount }).select('id').single();
  if (pe) return json({ error: 'Could not start the payment.' }, 500);

  const site = Deno.env.get('RETURN_URL') ?? 'https://nolifa-backoffice.web.app/paid.html';
  const res = await fetch('https://payments.yoco.com/api/checkouts', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount,
      currency: 'ZAR',
      successUrl: `${site}?ok=1`,
      cancelUrl: `${site}?cancelled=1`,
      failureUrl: `${site}?failed=1`,
      clientReferenceId: pay.id,
      metadata: { paymentId: pay.id, uid, tier: m.tier, kind: 'membership' },
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
