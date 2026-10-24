// Pulls live traffic incidents from TomTom for the areas Nolifa serves and keeps
// them in public.traffic_incidents. Runs every 5 minutes from the database.
// Needs the secrets NOTIFY_SECRET (shared with the other function) and TOMTOM_KEY.
import { createClient } from 'npm:@supabase/supabase-js@2';

// Each box stays under TomTom's 10 000 square kilometre limit.
const AREAS: Record<string, [number, number, number, number]> = {
  durban: [30.6, -30.2, 31.2, -29.5],
  southcoast: [30.1, -31.0, 30.9, -30.2],
  northcoast: [30.9, -29.5, 31.6, -28.8],
  midlands: [29.8, -30.0, 30.8, -29.2],
  zululand: [31.5, -29.0, 32.3, -28.4],
};

const FIELDS = '{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay,events{description,iconCategory},startTime,endTime,from,to,length,delay,roadNumbers}}}';

Deno.serve(async (req) => {
  if (req.headers.get('x-notify-secret') !== Deno.env.get('NOTIFY_SECRET')) return new Response('not allowed', { status: 401 });
  const key = Deno.env.get('TOMTOM_KEY');
  if (!key) return new Response(JSON.stringify({ note: 'no TomTom key set' }), { status: 200 });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const startedAt = new Date().toISOString();
  const seen = new Map<string, Record<string, unknown>>();
  const errors: string[] = [];

  for (const [name, [w, s, e, n]] of Object.entries(AREAS)) {
    const url = `https://api.tomtom.com/traffic/services/5/incidentDetails?key=${key}&bbox=${w},${s},${e},${n}&fields=${encodeURIComponent(FIELDS)}&language=en-GB&timeValidityFilter=present`;
    try {
      const res = await fetch(url);
      if (!res.ok) {
        errors.push(`${name}: ${res.status}`);
        continue;
      }
      const body = await res.json();
      for (const f of body.incidents ?? []) {
        const p = f.properties ?? {};
        const g = f.geometry ?? {};
        const pts: number[][] = g.type === 'Point' ? [g.coordinates] : g.coordinates ?? [];
        if (!p.id || pts.length === 0) continue;
        const mid = pts[Math.floor(pts.length / 2)];
        const ev = (p.events ?? [])[0] ?? {};
        seen.set(p.id, {
          id: p.id,
          category: p.iconCategory ?? 0,
          magnitude: p.magnitudeOfDelay ?? 0,
          description: ev.description ?? '',
          road: (p.roadNumbers ?? []).join(', '),
          from_place: p.from ?? '',
          to_place: p.to ?? '',
          lat: mid[1],
          lng: mid[0],
          length_m: Math.round(p.length ?? 0),
          delay_s: p.delay ?? null,
          starts_at: p.startTime ?? null,
          ends_at: p.endTime ?? null,
          area: name,
          seen_at: startedAt,
        });
      }
    } catch (err) {
      errors.push(`${name}: ${String(err).slice(0, 80)}`);
    }
  }

  const rows = [...seen.values()];
  for (let i = 0; i < rows.length; i += 400) {
    const { error } = await db.from('traffic_incidents').upsert(rows.slice(i, i + 400));
    if (error) errors.push(error.message);
  }
  // Only clear old rows when every area answered, so one failed call never wipes the map.
  if (errors.length === 0) await db.from('traffic_incidents').delete().lt('seen_at', startedAt);
  return new Response(JSON.stringify({ stored: rows.length, errors }), { status: 200 });
});
