// Turns the weekly "State of Dams" table for KwaZulu-Natal from the Department of
// Water and Sanitation into one water zone per supply system in public.water_zones.
// DWS changes weekly, so most runs add nothing. Needs the secret NOTIFY_SECRET
// (shared with the other functions).
//
// DWS refuses requests from data-centre addresses outside South Africa (HTTP 403),
// so the database job's own fetch is only a fallback. The dependable path is
// tools/sync_water.sh, which runs on a South African machine and posts the page
// here as {"html": "..."}.
//
// Dams are bulk storage. A healthy dam does not mean every tap is running, so the
// zones also take "dry taps" requests from verified people (see water_vote).
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL = 'https://www.dws.gov.za/Hydrology/Weekly/ProvinceWeek.aspx?region=KN';

type Dam = { name: string; river: string; fsc: number; thisWeek: number; lastWeek: number };

// Same systems as the apps' offline list (dws_feed.dart), so ids match.
const SYSTEMS: { id: string; name: string; provider: string; dams: string[] }[] = [
  { id: 'dws-durban', name: 'Greater Durban', provider: 'eThekwini Water and Sanitation, supplied by the Umgeni system', dams: ['Inanda Dam', 'Nagle Dam', 'Midmar Dam', 'Albert Falls Dam'] },
  { id: 'dws-midlands', name: 'KZN Midlands', provider: 'Msunduzi and uMgungundlovu, supplied by the Upper Umgeni and Mooi systems', dams: ['Midmar Dam', 'Albert Falls Dam', 'Spring Grove Dam', 'Mearns Dam'] },
  { id: 'dws-northcoast', name: 'North Coast', provider: 'iLembe, supplied by the Mdloti system', dams: ['Hazelmere Dam'] },
  { id: 'dws-zululand', name: 'Zululand', provider: 'King Cetshwayo and Zululand districts, supplied by the Mhlathuze, Hluhluwe and Pongola systems', dams: ['Goedertrouw Dam', 'Hluhluwe Dam', 'Pongolapoort Dam', 'Klipfontein Dam'] },
  { id: 'dws-northern', name: 'Northern KZN', provider: 'Newcastle and Uthukela, supplied by the Ngagane and Tugela systems', dams: ['Ntshingwayo Dam', 'Zaaihoek Dam', 'Spioenkop Dam', 'Wagendrift Dam', 'Woodstock Dam'] },
];

const DEFAULT_THRESHOLD = 10; // different verified people before a request reaches the provider

function text(html: string): string {
  return html.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim();
}

export function parseDws(html: string): { date: Date; day: string; dams: Dam[] } {
  const t = /State of Dams on (\d{4})-(\d{2})-(\d{2})/.exec(html);
  if (!t) throw new Error('not a State of Dams page');
  // The report date is a calendar day in South Africa (UTC+2).
  const date = new Date(Date.UTC(+t[1], +t[2] - 1, +t[3]) - 2 * 3600_000);
  const dams: Dam[] = [];
  for (const row of html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)) {
    const cells = [...row[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/g)].map((c) => text(c[1])).filter((c) => c);
    if (cells.length < 8 || !cells.includes('Photo')) continue;
    const at = cells.indexOf('Indicators');
    const nums = cells.slice(at + 1, at + 5).map((c) => parseFloat(c.replace('#', '')));
    if (nums.length < 4 || nums.some((n) => Number.isNaN(n))) continue;
    dams.push({ name: cells[0], river: cells[1], fsc: nums[0], thisWeek: nums[1], lastWeek: nums[2] });
  }
  if (dams.length === 0) throw new Error('no dams found');
  return { date, day: `${t[1]}-${t[2]}-${t[3]}`, dams };
}

// Share of the system's total storage that is full.
function level(dams: Dam[], names: string[], pick: (d: Dam) => number): number | null {
  const mine = dams.filter((d) => names.includes(d.name));
  if (mine.length === 0) return null;
  const cap = mine.reduce((a, d) => a + d.fsc, 0);
  const v = mine.reduce((a, d) => a + pick(d) * d.fsc, 0) / cap;
  return Math.min(100, Math.max(0, Math.round(v * 10) / 10));
}

Deno.serve(async (req) => {
  if (req.headers.get('x-notify-secret') !== Deno.env.get('NOTIFY_SECRET')) return new Response('not allowed', { status: 401 });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  let report;
  try {
    const sent = await req.json().then((b) => (typeof b?.html === 'string' ? (b.html as string) : null)).catch(() => null);
    if (sent) {
      report = parseDws(sent);
    } else {
      const res = await fetch(URL, { headers: { 'User-Agent': 'Nolifa/1.0 (community water radar)', Accept: '*/*' } });
      if (!res.ok) throw new Error(`DWS answered ${res.status}`);
      report = parseDws(await res.text());
    }
  } catch (err) {
    // Keep whatever is stored. Old readings are better than an empty map.
    return new Response(JSON.stringify({ stored: 0, error: String(err).slice(0, 120) }), { status: 200 });
  }

  const stamp = report.day;
  const source = `DWS weekly State of Dams, ${stamp}`;
  const { data: existing } = await db.from('water_zones').select('id, data').in('id', SYSTEMS.map((s) => s.id));
  const have = new Map((existing ?? []).map((r: { id: string; data: Record<string, unknown> }) => [r.id, r.data]));
  const changed: string[] = [];

  for (const s of SYSTEMS) {
    const now = level(report.dams, s.dams, (d) => d.thisWeek);
    const before = level(report.dams, s.dams, (d) => d.lastWeek);
    if (now === null || before === null) continue;
    const prev = have.get(s.id);
    // Provider changes to the threshold and population are kept.
    const readings: { t: number; level: number }[] = Array.isArray(prev?.readings) ? [...(prev!.readings as { t: number; level: number }[])] : [];
    const weekAgo = report.date.getTime() - 7 * 86400_000;
    if (readings.length === 0) readings.push({ t: weekAgo, level: before });
    if (readings[readings.length - 1].t < report.date.getTime()) readings.push({ t: report.date.getTime(), level: now });
    const data = {
      id: s.id,
      name: s.name,
      provider: s.provider,
      reservoir: s.dams.join(', '),
      population: (prev?.population as number | undefined) ?? 0,
      voteThreshold: (prev?.voteThreshold as number | undefined) ?? DEFAULT_THRESHOLD,
      readings: readings.slice(-48),
      latest: readings[readings.length - 1].level,
      source,
    };
    if (JSON.stringify(prev) !== JSON.stringify(data)) {
      const { error } = await db.from('water_zones').upsert({ id: s.id, data });
      if (error) return new Response(JSON.stringify({ stored: changed.length, error: error.message }), { status: 200 });
      changed.push(s.id);
    }
  }
  return new Response(JSON.stringify({ report: stamp, dams: report.dams.length, stored: changed.length, changed }), { status: 200 });
});
