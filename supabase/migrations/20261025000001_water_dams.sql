-- Real dam levels in the cloud, and a way to ask for water when the dam is full
-- but the tap is dry.
--
-- 1. water_zones is filled by the `water-dams` edge function from the weekly
--    State of Dams report (Department of Water and Sanitation).
-- 2. A zone may carry the name of its data source.
-- 3. water_vote takes a reason. "low_supply" still needs the level under 40%.
--    "dry_taps" does not: dams are bulk storage, and a burst main or a shutdown
--    can leave a street dry while the dam is 95% full. It still needs the same
--    number of different verified people before it reaches the provider.

create or replace function public.valid_zone(zid text, z jsonb) returns boolean
language sql immutable as $$
  select (select bool_and(k = any (array['id','name','provider','reservoir','population','voteThreshold','readings','latest','source']))
            from jsonb_object_keys(z) k)
    and z ->> 'id' = zid
    and jsonb_typeof(z -> 'name') = 'string' and length(z ->> 'name') between 1 and 80
    and jsonb_typeof(z -> 'provider') = 'string' and length(z ->> 'provider') <= 200
    and jsonb_typeof(z -> 'reservoir') = 'string' and length(z ->> 'reservoir') <= 200
    and jsonb_typeof(z -> 'population') = 'number' and (z ->> 'population')::numeric >= 0
    and jsonb_typeof(z -> 'voteThreshold') = 'number' and (z ->> 'voteThreshold')::numeric between 1 and 100000
    and jsonb_typeof(z -> 'readings') = 'array' and jsonb_array_length(z -> 'readings') <= 48
    and (public.jnull(z, 'latest') or (jsonb_typeof(z -> 'latest') = 'number' and (z ->> 'latest')::numeric between 0 and 100))
    and (public.jnull(z, 'source') or (jsonb_typeof(z -> 'source') = 'string' and length(z ->> 'source') <= 200))
$$;

drop function if exists public.water_vote(text);
create or replace function public.water_vote(p_zone text, p_reason text default 'low_supply') returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  z jsonb;
  inc public.water_incidents;
  epoch int;
  now_ms bigint := public.now_ms();
  thr int;
  votes int;
  enough boolean;
begin
  if not public.is_verified() then raise exception 'only verified people can vote' using errcode = '42501'; end if;
  if p_reason not in ('low_supply', 'dry_taps') then return 'notEligible'; end if;
  select data into z from public.water_zones where id = p_zone;
  if z is null then return 'notEligible'; end if;
  perform set_config('nolifa.internal', '1', true);

  -- Serialise voters on the zone so two first votes cannot open two incidents.
  perform 1 from public.water_zones where id = p_zone for update;

  select * into inc from public.water_incidents where zone_id = p_zone order by epoch desc limit 1;
  thr := coalesce((z ->> 'voteThreshold')::int, 100);

  if inc.id is null or inc.stage = 'resolved' then
    if p_reason = 'low_supply' and (public.jnull(z, 'latest') or (z ->> 'latest')::numeric >= 40) then
      perform set_config('nolifa.internal', '', true); return 'notEligible';
    end if;
    epoch := coalesce(inc.epoch, 0) + 1;
    enough := 1 >= thr;
    insert into public.water_incidents (id, zone_id, epoch, stage, data) values (
      p_zone || '-' || epoch, p_zone, epoch, case when enough then 'requested' else 'open' end,
      jsonb_build_object('id', p_zone || '-' || epoch, 'zoneId', p_zone, 'epoch', epoch,
        'stage', case when enough then 'requested' else 'open' end, 'votes', 1, 'threshold', thr,
        'openedAt', now_ms, 'requestedAt', case when enough then to_jsonb(now_ms) else 'null'::jsonb end,
        'acknowledgedAt', null, 'dispatchedAt', null, 'resolvedAt', null,
        'trucks', 0, 'etaMinutes', 0, 'note', '', 'reason', p_reason));
    insert into public.water_votes (incident_id, uid, at) values (p_zone || '-' || epoch, v_uid, now_ms);
    perform set_config('nolifa.internal', '', true); return 'counted';
  end if;

  if inc.stage not in ('open','requested') then perform set_config('nolifa.internal', '', true); return 'notEligible'; end if;
  if exists (select 1 from public.water_votes where incident_id = inc.id and water_votes.uid = v_uid) then
    perform set_config('nolifa.internal', '', true); return 'alreadyVoted';
  end if;
  votes := coalesce((inc.data ->> 'votes')::int, 0) + 1;
  insert into public.water_votes (incident_id, uid, at) values (inc.id, v_uid, now_ms);
  if inc.stage = 'open' and votes >= coalesce((inc.data ->> 'threshold')::int, 100) then
    update public.water_incidents set stage = 'requested',
      data = inc.data || jsonb_build_object('votes', votes, 'stage', 'requested', 'requestedAt', now_ms)
      where id = inc.id;
  else
    update public.water_incidents set data = inc.data || jsonb_build_object('votes', votes) where id = inc.id;
  end if;
  perform set_config('nolifa.internal', '', true); return 'counted';
end $$;
grant execute on function public.water_vote(text, text) to authenticated;

-- The dam job runs once a day. DWS updates its table weekly, so most runs only
-- confirm what is already stored; the function adds a reading only for a new week.
alter table public.notify_config add column if not exists water_url text;

create or replace function public.run_water_dams() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c public.notify_config;
begin
  select * into c from public.notify_config where id = 1;
  if c.water_url is null then return; end if;
  perform net.http_post(url := c.water_url, headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', c.function_secret), body := '{}'::jsonb);
exception when others then
  null;
end $$;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('nolifa-water-dams', '0 4 * * *', 'select public.run_water_dams()');
exception when others then
  raise notice 'water schedule not set: %', sqlerrm;
end $$;
