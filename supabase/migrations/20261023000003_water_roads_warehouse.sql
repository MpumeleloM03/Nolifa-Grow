-- Water radar, road hazards and the Nolifa warehouse.

create or replace function public.jtext_array(j jsonb, k text) returns text[]
language sql immutable as $$
  select coalesce((select array_agg(x) from jsonb_array_elements_text(
    case when jsonb_typeof(j -> k) = 'array' then j -> k else '[]'::jsonb end) x), '{}')
$$;

-- ───────── Water ─────────
create table public.water_zones (id text primary key, data jsonb not null);
create table public.water_incidents (
  id text primary key,
  zone_id text not null,
  epoch int not null,
  stage text not null,
  data jsonb not null
);
create table public.water_votes (
  incident_id text not null references public.water_incidents (id),
  uid text not null,
  at bigint not null,
  primary key (incident_id, uid)
);
create table public.water_prefs (uid text primary key, data jsonb not null);
alter table public.water_zones enable row level security;
alter table public.water_incidents enable row level security;
alter table public.water_votes enable row level security;
alter table public.water_prefs enable row level security;

create or replace function public.valid_zone(zid text, z jsonb) returns boolean
language sql immutable as $$
  select (select bool_and(k = any (array['id','name','provider','reservoir','population','voteThreshold','readings','latest']))
            from jsonb_object_keys(z) k)
    and z ->> 'id' = zid
    and jsonb_typeof(z -> 'name') = 'string' and length(z ->> 'name') between 1 and 80
    and jsonb_typeof(z -> 'provider') = 'string' and length(z ->> 'provider') <= 80
    and jsonb_typeof(z -> 'reservoir') = 'string' and length(z ->> 'reservoir') <= 80
    and jsonb_typeof(z -> 'population') = 'number' and (z ->> 'population')::numeric >= 0
    and jsonb_typeof(z -> 'voteThreshold') = 'number' and (z ->> 'voteThreshold')::numeric between 1 and 100000
    and jsonb_typeof(z -> 'readings') = 'array' and jsonb_array_length(z -> 'readings') <= 48
    and (public.jnull(z, 'latest') or (jsonb_typeof(z -> 'latest') = 'number' and (z ->> 'latest')::numeric between 0 and 100))
$$;

create policy zones_read on public.water_zones for select to authenticated using (true);
create policy zones_write on public.water_zones for insert to authenticated
  with check (public.is_utility() and public.valid_zone(id, data));
create policy zones_update on public.water_zones for update to authenticated
  using (public.is_utility()) with check (public.is_utility() and public.valid_zone(id, data));

create policy incidents_read on public.water_incidents for select to authenticated using (true);
create policy incidents_provider on public.water_incidents for update to authenticated
  using (public.is_utility()) with check (public.is_utility());
-- A person sees only their own vote; the public number is the incident counter.
create policy votes_self on public.water_votes for select to authenticated using (uid = auth.uid()::text);

create or replace function public.water_incidents_guard() returns trigger language plpgsql as $$
declare
  o jsonb := old.data;
  n jsonb := new.data;
  ch text[] := public.changed_keys(old.data, new.data);
  ok boolean := false;
begin
  if auth.uid() is null or current_setting('nolifa.internal', true) = '1' then return new; end if;
  if not public.is_utility() then raise exception 'only the water provider can do that' using errcode = '42501'; end if;
  if o ->> 'stage' = 'requested' and n ->> 'stage' = 'acknowledged' and jsonb_typeof(n -> 'acknowledgedAt') = 'number'
     and ch <@ array['stage','acknowledgedAt'] then ok := true; end if;
  if not ok and o ->> 'stage' in ('requested','acknowledged') and n ->> 'stage' = 'dispatched'
     and jsonb_typeof(n -> 'dispatchedAt') = 'number'
     and (n ->> 'trucks')::int between 1 and 20 and (n ->> 'etaMinutes')::int between 1 and 1440
     and length(n ->> 'note') <= 280
     and ch <@ array['stage','dispatchedAt','trucks','etaMinutes','note'] then ok := true; end if;
  if not ok and o ->> 'stage' = 'dispatched' and n ->> 'stage' = 'resolved' and jsonb_typeof(n -> 'resolvedAt') = 'number'
     and ch <@ array['stage','resolvedAt'] then ok := true; end if;
  if not ok then raise exception 'that incident change is not allowed' using errcode = '42501'; end if;
  new.stage := n ->> 'stage';
  return new;
end $$;
create trigger b_water_incidents_guard before update on public.water_incidents
  for each row execute function public.water_incidents_guard();

-- One person, one vote per incident. The vote and the counter move together.
create or replace function public.water_vote(p_zone text) returns text
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
  select data into z from public.water_zones where id = p_zone;
  if z is null then return 'notEligible'; end if;
  perform set_config('nolifa.internal', '1', true);

  -- Serialise voters on the zone so two first votes cannot open two incidents.
  perform 1 from public.water_zones where id = p_zone for update;

  select * into inc from public.water_incidents where zone_id = p_zone order by epoch desc limit 1;
  thr := coalesce((z ->> 'voteThreshold')::int, 100);

  if inc.id is null or inc.stage = 'resolved' then
    if public.jnull(z, 'latest') or (z ->> 'latest')::numeric >= 40 then perform set_config('nolifa.internal', '', true); return 'notEligible'; end if;
    epoch := coalesce(inc.epoch, 0) + 1;
    enough := 1 >= thr;
    insert into public.water_incidents (id, zone_id, epoch, stage, data) values (
      p_zone || '-' || epoch, p_zone, epoch, case when enough then 'requested' else 'open' end,
      jsonb_build_object('id', p_zone || '-' || epoch, 'zoneId', p_zone, 'epoch', epoch,
        'stage', case when enough then 'requested' else 'open' end, 'votes', 1, 'threshold', thr,
        'openedAt', now_ms, 'requestedAt', case when enough then to_jsonb(now_ms) else 'null'::jsonb end,
        'acknowledgedAt', null, 'dispatchedAt', null, 'resolvedAt', null,
        'trucks', 0, 'etaMinutes', 0, 'note', ''));
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

create or replace function public.water_has_voted(p_incident text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.water_votes where incident_id = p_incident and uid = auth.uid()::text)
$$;

create policy prefs_owner on public.water_prefs for all to authenticated
  using (uid = auth.uid()::text)
  with check (uid = auth.uid()::text
    and (select bool_and(k = any (array['zoneId','household','tankLitres','herd'])) from jsonb_object_keys(data) k)
    and (public.jnull(data, 'zoneId') or length(data ->> 'zoneId') <= 100)
    and (data ->> 'household')::int between 0 and 1000
    and (data ->> 'tankLitres')::int between 0 and 10000000
    and (data ->> 'herd')::int between 0 and 1000000);

-- ───────── Road hazards ─────────
create table public.road_hazards (
  id text primary key,
  last_seen bigint not null,
  data jsonb not null
);
create index road_hazards_last_seen on public.road_hazards (last_seen);
alter table public.road_hazards enable row level security;

create or replace function public.road_recent(ms bigint) returns boolean
language sql stable as $$ select ms <= public.now_ms() + 120000 and ms >= public.now_ms() - 600000 $$;

create policy hazards_read on public.road_hazards for select to authenticated using (true);
create policy hazards_create on public.road_hazards for insert to authenticated with check (
  public.is_verified()
  and (select bool_and(k = any (array['kind','lat','lng','reportedAt','lastSeen','reporter','reporterName','confirms','denies','note']))
         from jsonb_object_keys(data) k)
  and data ->> 'kind' in ('pothole','flooding','accident','roadworks','blocked','police','outage','animals')
  and jsonb_typeof(data -> 'lat') = 'number' and (data ->> 'lat')::numeric between -35 and -22
  and jsonb_typeof(data -> 'lng') = 'number' and (data ->> 'lng')::numeric between 16 and 33
  and data ->> 'reporter' = auth.uid()::text
  and data -> 'confirms' = to_jsonb(array[auth.uid()::text])
  and data -> 'denies' = '[]'::jsonb
  and public.road_recent((data ->> 'reportedAt')::bigint)
  and data -> 'lastSeen' = data -> 'reportedAt'
  and jsonb_typeof(data -> 'reporterName') = 'string' and length(data ->> 'reporterName') <= 60
  and jsonb_typeof(data -> 'note') = 'string' and length(data ->> 'note') <= 140
  and last_seen = (data ->> 'lastSeen')::bigint);
create policy hazards_update on public.road_hazards for update to authenticated
  using (public.is_verified()) with check (public.is_verified());

create or replace function public.road_hazards_guard() returns trigger language plpgsql as $$
declare
  uid text := auth.uid()::text;
  o jsonb := old.data;
  n jsonb := new.data;
  oc text[] := public.jtext_array(o, 'confirms');
  nc text[] := public.jtext_array(n, 'confirms');
  od text[] := public.jtext_array(o, 'denies');
  nd text[] := public.jtext_array(n, 'denies');
  saw boolean;
  gone boolean;
begin
  if uid is null then return new; end if;
  new.last_seen := (n ->> 'lastSeen')::bigint;
  if not (public.changed_keys(o, n) <@ array['confirms','denies','lastSeen']) then
    raise exception 'that warning change is not allowed' using errcode = '42501';
  end if;
  saw := uid = any (nc) and nc @> oc and cardinality(nc) <= cardinality(oc) + 1
     and not exists (select 1 from unnest(nc) x where x <> all (oc) and x <> uid)
     and od @> nd and nd @> array_remove(od, uid)
     and public.road_recent((n ->> 'lastSeen')::bigint) and (n ->> 'lastSeen')::bigint >= (o ->> 'lastSeen')::bigint;
  gone := uid = any (nd) and nd @> od and cardinality(nd) <= cardinality(od) + 1
     and not exists (select 1 from unnest(nd) x where x <> all (od) and x <> uid)
     and oc @> nc and nc @> array_remove(oc, uid)
     and (o ->> 'reporter') = any (nc) and n -> 'lastSeen' = o -> 'lastSeen';
  if not (saw or gone) then raise exception 'that warning change is not allowed' using errcode = '42501'; end if;
  return new;
end $$;
create trigger b_road_hazards_guard before update on public.road_hazards
  for each row execute function public.road_hazards_guard();

-- ───────── Warehouse ─────────
create table public.warehouse_lots (id text primary key, data jsonb not null, farmer_id text);
create table public.warehouse_readings (id text primary key, at bigint not null, data jsonb not null);
create table public.warehouse_certs (id text primary key, data jsonb not null, certifier_id text);
create table public.warehouse_picks (id text primary key, data jsonb not null);
alter table public.warehouse_lots enable row level security;
alter table public.warehouse_readings enable row level security;
alter table public.warehouse_certs enable row level security;
alter table public.warehouse_picks enable row level security;

create or replace function public.warehouse_cols() returns trigger language plpgsql as $$
begin
  if tg_table_name = 'warehouse_lots' then new.farmer_id := new.data ->> 'farmerId'; end if;
  if tg_table_name = 'warehouse_certs' then new.certifier_id := new.data ->> 'certifierId'; end if;
  if tg_table_name = 'warehouse_readings' then new.at := coalesce((new.data ->> 'at')::bigint, new.at); end if;
  return new;
end $$;
create trigger a_lots_cols before insert or update on public.warehouse_lots for each row execute function public.warehouse_cols();
create trigger a_certs_cols before insert or update on public.warehouse_certs for each row execute function public.warehouse_cols();
create trigger a_readings_cols before insert or update on public.warehouse_readings for each row execute function public.warehouse_cols();

create policy lots_read on public.warehouse_lots for select to authenticated
  using (farmer_id = auth.uid()::text or public.is_hub_staff());
create policy lots_announce on public.warehouse_lots for insert to authenticated with check (
  public.is_verified()
  and farmer_id = auth.uid()::text
  and data ->> 'status' = 'expected'
  and (data ->> 'remaining')::numeric = 0
  and public.jnull(data, 'tag')
  and jsonb_typeof(data -> 'qty') = 'number' and (data ->> 'qty')::numeric > 0
  and data ->> 'zone' in ('frozen','chilled','cool','ambient'));
create policy lots_staff on public.warehouse_lots for update to authenticated
  using (public.is_hub_staff()) with check (public.is_hub_staff());

create or replace function public.warehouse_lots_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  if old.data -> 'farmerId' = new.data -> 'farmerId' and old.data -> 'product' = new.data -> 'product'
     and old.data -> 'zone' = new.data -> 'zone' and old.data -> 'useBy' is not distinct from new.data -> 'useBy' then
    return new;
  end if;
  raise exception 'that lot change is not allowed' using errcode = '42501';
end $$;
create trigger b_lots_guard before update on public.warehouse_lots
  for each row execute function public.warehouse_lots_guard();

create policy picks_staff on public.warehouse_picks for all to authenticated
  using (public.is_hub_staff()) with check (public.is_hub_staff());

create policy readings_read on public.warehouse_readings for select to authenticated using (public.is_hub_staff());
create policy readings_add on public.warehouse_readings for insert to authenticated with check (public.is_hub_staff());

create policy certs_read on public.warehouse_certs for select to authenticated
  using (public.is_hub_staff() or public.is_certifier());
create policy certs_add on public.warehouse_certs for insert to authenticated with check (
  public.is_certifier()
  and certifier_id = auth.uid()::text
  and jsonb_typeof(data -> 'rooms') = 'array' and jsonb_array_length(data -> 'rooms') > 0
  and jsonb_typeof(data -> 'expiresAt') = 'number' and jsonb_typeof(data -> 'issuedAt') = 'number'
  and (data ->> 'expiresAt')::numeric > (data ->> 'issuedAt')::numeric);

-- ───────── Realtime ─────────
alter publication supabase_realtime add table
  public.market_products, public.market_orders, public.market_cases, public.outbreaks,
  public.water_zones, public.water_incidents, public.road_hazards,
  public.warehouse_lots, public.warehouse_readings, public.warehouse_certs;

-- Record what was cut for one order line; lines already cut stay as they are.
create or replace function public.save_pick(p_order text, p_index text, p_line jsonb) returns void
language plpgsql as $$
begin
  if not public.is_hub_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  insert into public.warehouse_picks (id, data)
  values (p_order, jsonb_build_object('orderId', p_order, 'lines', jsonb_build_object(p_index, p_line)))
  on conflict (id) do update
    set data = public.warehouse_picks.data || jsonb_build_object(
      'lines', coalesce(public.warehouse_picks.data -> 'lines', '{}'::jsonb) || jsonb_build_object(p_index, p_line));
end $$;

-- Create or update in one call. A plain upsert would run the create rules on a
-- row that already exists, so these choose the right rule themselves.
create or replace function public.save_hazard(p_id text, p_data jsonb) returns void
language plpgsql as $$
begin
  if exists (select 1 from public.road_hazards where id = p_id) then
    update public.road_hazards set data = p_data, last_seen = (p_data ->> 'lastSeen')::bigint where id = p_id;
  else
    insert into public.road_hazards (id, last_seen, data) values (p_id, (p_data ->> 'lastSeen')::bigint, p_data);
  end if;
end $$;

create or replace function public.save_lot(p_id text, p_data jsonb) returns void
language plpgsql as $$
begin
  if exists (select 1 from public.warehouse_lots where id = p_id) then
    update public.warehouse_lots set data = p_data where id = p_id;
  else
    insert into public.warehouse_lots (id, data) values (p_id, p_data);
  end if;
end $$;
