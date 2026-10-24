// Sends a leaf photo to Plant.id and returns a short diagnosis. The Plant.id key
// lives here as the secret PLANT_ID_KEY, never in the app. Only signed-in people
// can use it, and each gets PLANT_ID_DAILY checks a day (default 25).
//
// The reply is { label, confidence, isHealthy, diseases[] }, or
// { error: 'limit' | 'unavailable' } with a matching status, in which case the
// app falls back to the model on the phone.
import { createClient } from 'npm:@supabase/supabase-js@2';

const API = 'https://plant.id/api/v3/health_assessment';
const MAX_BASE64 = 3_500_000; // about 2.6 MB of image

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'post only' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json({ error: 'sign in' }, 401);

  const key = Deno.env.get('PLANT_ID_KEY');
  if (!key) return json({ error: 'unavailable' }, 503);

  let image: string;
  try {
    const body = await req.json();
    image = String(body.image ?? '');
  } catch {
    return json({ error: 'bad request' }, 400);
  }
  if (image.length < 100 || image.length > MAX_BASE64) return json({ error: 'bad image' }, 400);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const limit = Number(Deno.env.get('PLANT_ID_DAILY') ?? '25');
  const { data: allowed } = await admin.rpc('plant_scan_take', { p_uid: user.id, p_limit: limit });
  if (allowed === false) return json({ error: 'limit' }, 429);

  try {
    const res = await fetch(API, {
      method: 'POST',
      headers: { 'Api-Key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ images: [image], health: 'all' }),
    });
    if (!res.ok) return json({ error: 'unavailable', status: res.status }, 502);
    const result = (await res.json()).result;
    const healthy = result?.is_healthy;
    if (healthy?.binary === true) {
      return json({ label: 'Healthy', confidence: (healthy.probability * 100).toFixed(1), isHealthy: true, diseases: [] });
    }
    const list: { name: string; probability: number }[] = result?.disease?.suggestions ?? [];
    if (list.length === 0) return json({ label: 'Unknown', confidence: '0', isHealthy: false, diseases: [] });
    return json({
      label: list[0].name,
      confidence: (list[0].probability * 100).toFixed(1),
      isHealthy: false,
      diseases: list.slice(0, 3).map((d) => ({ name: d.name, confidence: (d.probability * 100).toFixed(1) })),
    });
  } catch {
    return json({ error: 'unavailable' }, 502);
  }
});
