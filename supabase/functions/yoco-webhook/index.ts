// Receives Yoco's signed payment messages. A membership or an order is only marked paid after the
// signature checks out, the message is fresh, and the checkout is one we made.
import { createClient } from 'npm:@supabase/supabase-js@2';

const enc = new TextEncoder();

function b64decode(s: string): Uint8Array {
  const bin = atob(s);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function signatureOk(secret: string, id: string, ts: string, raw: string, header: string): Promise<boolean> {
  const key = await crypto.subtle.importKey('raw', b64decode(secret.replace(/^whsec_/, '')), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(`${id}.${ts}.${raw}`));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return header.split(' ').some((part) => same(part.split(',')[1] ?? '', expected));
}

Deno.serve(async (req) => {
  const secret = Deno.env.get('YOCO_WEBHOOK_SECRET');
  if (!secret) return new Response('not set up', { status: 503 });
  const raw = await req.text();
  const id = req.headers.get('webhook-id') ?? '';
  const ts = req.headers.get('webhook-timestamp') ?? '';
  const sig = req.headers.get('webhook-signature') ?? '';
  if (!id || !ts || !sig) return new Response('bad request', { status: 400 });
  // Reject anything older than 3 minutes, so a captured message cannot be replayed later.
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 180) return new Response('stale', { status: 403 });
  if (!(await signatureOk(secret, id, ts, raw, sig))) return new Response('bad signature', { status: 403 });

  let event: any;
  try {
    event = JSON.parse(raw);
  } catch {
    return new Response('bad json', { status: 400 });
  }
  if (event.type !== 'payment.succeeded') return new Response('ignored', { status: 200 });
  const meta = event.payload?.metadata ?? {};
  const paymentId = meta.paymentId;
  const checkoutId = meta.checkoutId;
  if (!paymentId || !checkoutId) return new Response('no reference', { status: 200 });

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  // An order or a membership: the payment row says which.
  const { data: row } = await db.from('payments').select('kind').eq('id', paymentId).maybeSingle();
  const { data, error } = row?.kind === 'order'
    ? await db.rpc('activate_order_paid', { p_payment: paymentId, p_checkout: checkoutId })
    : await db.rpc('activate_membership_paid', { p_payment: paymentId, p_checkout: checkoutId });
  if (error) return new Response('could not record', { status: 500 });
  return new Response(JSON.stringify({ result: data }), { status: 200 });
});
