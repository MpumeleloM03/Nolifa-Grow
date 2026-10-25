-- One backend, three clear doors, and the live pieces that join them.
--
--  * drop_api   what a household sees: farms and what is in stock, an order's live track.
--  * grow_api   what a seller sees: their stock in the shop and in the warehouse, the room
--               temperature, orders for their farm, truck hire.
--  * delivery_api  what a driver sees: location posting, their jobs' money.
--  Each door is a Postgres schema of small functions. The apps call these; row level
--  security on the tables underneath still decides who can read what.
--
--  Live pieces: notifications (approvals, orders, payouts, cold-room alarms), driver
--  locations, the room temperature a farmer may see, truck hire.

-- ───────── Notifications ─────────
create table public.notifications (
  id bigint generated always as identity primary key,
  uid text not null,
  kind text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_uid on public.notifications (uid, created_at desc);
alter table public.notifications enable row level security;
create policy notifications_own on public.notifications for select to authenticated using (uid = auth.uid()::text);

create or replace function public.notify_user(p_uid text, p_kind text, p_title text, p_body text default '', p_data jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_uid is null or p_uid = '' then return; end if;
  insert into public.notifications (uid, kind, title, body, data) values (p_uid, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'));
end $$;
revoke all on function public.notify_user(text, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.mark_notifications_read(p_up_to bigint default null) returns void
language sql security definer set search_path = public as $$
  update public.notifications set read_at = now()
   where uid = auth.uid()::text and read_at is null and (p_up_to is null or id <= p_up_to)
$$;
grant execute on function public.mark_notifications_read(bigint) to authenticated;

-- Application decisions reach the person the moment staff decide.
create or replace function public.trg_application_notice() returns trigger
language plpgsql security definer set search_path = public as $$
declare what text := tg_argv[0]; t text; b text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'approved' then
    if what = 'farm' then
      t := 'Your farm is approved'; b := 'You can sell on Nolifa now. Add your stock and your store is open.';
    else
      t := 'You are approved to drive'; b := 'Go online to see delivery jobs near you.';
    end if;
  elsif new.status = 'needs_info' then
    t := 'We need a bit more'; b := coalesce(nullif(new.review_note, ''), 'Open your application to see what is missing.');
  elsif new.status = 'rejected' then
    t := 'Application not approved'; b := coalesce(nullif(new.review_note, ''), 'Open your application to see why.');
  else
    return new;
  end if;
  perform public.notify_user(new.uid, what || '_application', t, b, jsonb_build_object('status', new.status));
  return new;
end $$;
create trigger z_farm_application_notice after update of status on public.farm_applications
  for each row execute function public.trg_application_notice('farm');
create trigger z_driver_application_notice after update of status on public.driver_applications
  for each row execute function public.trg_application_notice('driver');

create or replace function public.trg_membership_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'active' and old.status is distinct from 'active' then
    perform public.notify_user(new.uid, 'membership', 'Your membership is on',
      case new.tier when 'max' then 'Max: 15 vet videos a month, on-site vet visits and the borehole discount are open.'
                    else 'Member: 4 vet videos a month and the borehole discount are open.' end,
      jsonb_build_object('tier', new.tier));
  end if;
  return new;
end $$;
create trigger z_membership_notice after update of status on public.memberships
  for each row execute function public.trg_membership_notice();

create or replace function public.trg_plan_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.plan is distinct from old.plan then
    perform public.notify_user(new.uid, 'plan', 'Your plan is ' || initcap(new.plan),
      case new.plan when 'coop' then 'Commission is 3% per sale.' when 'grow' then 'Commission is 5% per sale.' else 'Commission is 8% per sale.' end,
      jsonb_build_object('plan', new.plan));
  end if;
  return new;
end $$;
create trigger z_plan_notice after insert or update of plan on public.seller_plans
  for each row execute function public.trg_plan_notice();

create or replace function public.trg_borehole_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('quoted', 'scheduled', 'drilled') then
    perform public.notify_user(new.uid, 'borehole', case new.status
      when 'quoted' then 'Your borehole quote is ready' when 'scheduled' then 'Your borehole is booked' else 'Your borehole is drilled' end,
      'Open the borehole page for the details.', jsonb_build_object('status', new.status));
  end if;
  return new;
end $$;
create trigger z_borehole_notice after update of status on public.borehole_requests
  for each row execute function public.trg_borehole_notice();

-- Orders: the seller hears about a new order, the buyer follows the delivery.
create or replace function public.trg_order_notice() returns trigger
language plpgsql security definer set search_path = public as $$
declare d jsonb := new.data; short text := right(new.id, 5);
begin
  if tg_op = 'INSERT' then
    perform public.notify_user(new.farmer_id, 'order_new', 'New order ' || short,
      coalesce(d ->> 'customer', 'A neighbour') || ' ordered from your farm. Pack it and send it out.', jsonb_build_object('order', new.id));
    return new;
  end if;
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'findingDriver' then
    perform public.notify_user(new.customer_id, 'order_packed', 'Order ' || short || ' is packed', 'We are finding a driver.', jsonb_build_object('order', new.id));
  elsif new.status = 'assigned' then
    perform public.notify_user(new.customer_id, 'order_driver', 'A driver is on the way', coalesce(d ->> 'driver', 'Your driver') || ' is collecting order ' || short || '. Follow it live.', jsonb_build_object('order', new.id));
    perform public.notify_user(new.farmer_id, 'order_driver', 'Driver coming for order ' || short, coalesce(d ->> 'driver', 'A driver') || ' is on the way to collect it.', jsonb_build_object('order', new.id));
  elsif new.status = 'pickedUp' then
    perform public.notify_user(new.customer_id, 'order_pickedup', 'Order ' || short || ' is on its way', 'Have your 4-digit PIN ready for the driver.', jsonb_build_object('order', new.id));
  elsif new.status = 'delivered' then
    perform public.notify_user(new.customer_id, 'order_delivered', 'Order ' || short || ' delivered', 'Confirm you got everything to pay the farm and driver.', jsonb_build_object('order', new.id));
    perform public.notify_user(new.farmer_id, 'order_delivered', 'Order ' || short || ' delivered', 'The payout follows when the buyer confirms.', jsonb_build_object('order', new.id));
  end if;
  return new;
end $$;
create trigger z_order_notice after insert or update on public.market_orders
  for each row execute function public.trg_order_notice();

create or replace function public.trg_payout_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.state = 'released' and old.state is distinct from 'released' then
    perform public.notify_user(new.driver_id, 'payout', 'R' || to_char(new.amount, 'FM999990.00') || ' paid', 'Delivery ' || right(new.order_id, 5) || ' is paid out.', jsonb_build_object('order', new.order_id));
  end if;
  return new;
end $$;
create trigger z_payout_notice after update of state on public.driver_payouts
  for each row execute function public.trg_payout_notice();

-- ───────── Driver locations ─────────
create table public.driver_locations (
  driver_id text primary key,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  heading real,
  speed_kmh real,
  accuracy_m real,
  online boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.driver_locations enable row level security;
-- A driver sees themselves. Staff see every driver. A buyer or seller sees the
-- driver of an order that is on its way, and nobody else.
create policy driver_locations_read on public.driver_locations for select to authenticated using (
  driver_id = auth.uid()::text
  or public.is_hub_staff() or public.is_admin()
  or exists (select 1 from public.market_orders o
             where o.driver_id = driver_locations.driver_id
               and o.status in ('assigned', 'pickedUp')
               and (o.customer_id = auth.uid()::text or o.farmer_id = auth.uid()::text)));

create or replace function public.post_location(p_lat double precision, p_lng double precision,
    p_heading real default null, p_speed real default null, p_accuracy real default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if not public.is_approved_driver() then raise exception 'Only approved drivers can share a location.' using errcode = '42501'; end if;
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Bad position.' using errcode = 'P0001'; end if;
  insert into public.driver_locations (driver_id, lat, lng, heading, speed_kmh, accuracy_m, online, updated_at)
  values (v_uid, p_lat, p_lng, p_heading, p_speed, p_accuracy, true, now())
  on conflict (driver_id) do update set lat = excluded.lat, lng = excluded.lng, heading = excluded.heading,
    speed_kmh = excluded.speed_kmh, accuracy_m = excluded.accuracy_m, online = true, updated_at = now()
  where public.driver_locations.updated_at < now() - interval '2 seconds';
end $$;
grant execute on function public.post_location(double precision, double precision, real, real, real) to authenticated;

create or replace function public.go_offline() returns void
language sql security definer set search_path = public as $$
  update public.driver_locations set online = false, updated_at = now() where driver_id = auth.uid()::text
$$;
grant execute on function public.go_offline() to authenticated;

-- ───────── Room climate: what a farmer may see about their stock ─────────
create or replace function public.zone_ok(p_zone text, p_c numeric) returns boolean
language sql immutable as $$
  select case p_zone when 'frozen' then p_c between -26 and -14
                     when 'chilled' then p_c between -1 and 5
                     when 'cool' then p_c between 7 and 13
                     else p_c between 9 and 26 end
$$;

create table public.room_climate (
  hub text not null,
  zone text not null,
  c numeric not null,
  ok boolean not null,
  at bigint not null,
  manual boolean not null default false,
  primary key (hub, zone)
);
alter table public.room_climate enable row level security;
create policy room_climate_read on public.room_climate for select to authenticated using (
  public.is_hub_staff() or public.is_admin()
  or exists (select 1 from public.warehouse_lots l
             where l.farmer_id = auth.uid()::text
               and l.data ->> 'zone' = room_climate.zone
               and coalesce(l.data ->> 'hub', 'Durban hub') = room_climate.hub
               and l.data ->> 'status' in ('expected', 'stored')));

create or replace function public.trg_room_climate() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_hub text := coalesce(new.data ->> 'hub', 'Durban hub');
  v_zone text := new.data ->> 'zone';
  v_c numeric := (new.data ->> 'c')::numeric;
  v_ok boolean;
  was_ok boolean;
  r record;
begin
  if v_zone is null or v_c is null then return new; end if;
  v_ok := public.zone_ok(v_zone, v_c);
  select ok into was_ok from public.room_climate where hub = v_hub and zone = v_zone;
  insert into public.room_climate (hub, zone, c, ok, at, manual)
  values (v_hub, v_zone, v_c, v_ok, new.at, coalesce((new.data ->> 'manual')::boolean, false))
  on conflict (hub, zone) do update set c = excluded.c, ok = excluded.ok, at = excluded.at, manual = excluded.manual;
  -- Out of range now, and it was fine before: tell everyone with stock in the room.
  if not v_ok and coalesce(was_ok, true) then
    for r in select distinct farmer_id, data ->> 'product' as product from public.warehouse_lots
              where data ->> 'zone' = v_zone and coalesce(data ->> 'hub', 'Durban hub') = v_hub
                and data ->> 'status' = 'stored' and (data ->> 'remaining')::numeric > 0 loop
      perform public.notify_user(r.farmer_id, 'cold_alarm', 'Temperature alert for your ' || coalesce(r.product, 'stock'),
        'The ' || v_zone || ' room read ' || v_c::text || ' C. Warehouse staff have been told.', jsonb_build_object('zone', v_zone, 'c', v_c));
    end loop;
  end if;
  return new;
end $$;
create trigger z_room_climate after insert on public.warehouse_readings
  for each row execute function public.trg_room_climate();

-- What is already recorded becomes the current state of each room.
insert into public.room_climate (hub, zone, c, ok, at, manual)
select distinct on (coalesce(data ->> 'hub', 'Durban hub'), data ->> 'zone')
       coalesce(data ->> 'hub', 'Durban hub'), data ->> 'zone', (data ->> 'c')::numeric,
       public.zone_ok(data ->> 'zone', (data ->> 'c')::numeric), at, coalesce((data ->> 'manual')::boolean, false)
  from public.warehouse_readings
 where data ->> 'zone' is not null and data ->> 'c' is not null
 order by coalesce(data ->> 'hub', 'Durban hub'), data ->> 'zone', at desc
on conflict do nothing;

-- ───────── Truck hire ─────────
create table public.truck_hire (
  id text primary key default gen_random_uuid()::text,
  uid text not null,
  farm_name text not null default '',
  kind text not null check (kind in ('bakkie', 'refrigerated', 'flatbed')),
  load_kg int not null check (load_kg between 1 and 30000),
  cold_chain boolean not null default false,
  from_place text not null check (length(from_place) between 2 and 120),
  to_place text not null check (length(to_place) between 2 and 120),
  km numeric(7, 1) not null check (km between 1 and 1500),
  needed_on date not null,
  notes text not null default '' check (length(notes) <= 400),
  estimate numeric(10, 2) not null,
  quote numeric(10, 2),
  status text not null default 'requested' check (status in ('requested', 'quoted', 'booked', 'done', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index truck_hire_uid on public.truck_hire (uid, created_at desc);
alter table public.truck_hire enable row level security;
create policy truck_hire_read on public.truck_hire for select to authenticated
  using (uid = auth.uid()::text or public.is_hub_staff() or public.is_admin());

-- Indicative price: a call-out plus the distance. Staff confirm the real quote.
create or replace function public.truck_estimate(p_kind text, p_km numeric, p_cold boolean) returns numeric
language sql immutable as $$
  select round((case p_kind when 'refrigerated' then 900 + 22 * p_km when 'flatbed' then 600 + 15 * p_km else 350 + 9.5 * p_km end
                * case when p_cold and p_kind <> 'refrigerated' then 1.15 else 1 end)::numeric, 0)
$$;

create or replace function public.request_truck(p_kind text, p_load_kg int, p_cold boolean, p_from text, p_to text,
    p_km numeric, p_needed_on date, p_notes text default '') returns text
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text; v_id text; v_farm text; v_email text;
begin
  if v_uid is null or not public.is_verified() then raise exception 'Only verified farms can hire a truck.' using errcode = '42501'; end if;
  if p_needed_on < current_date then raise exception 'Pick a day from today.' using errcode = 'P0001'; end if;
  if p_cold and p_kind = 'flatbed' then raise exception 'A flatbed cannot keep goods cold. Pick a refrigerated truck.' using errcode = 'P0001'; end if;
  select coalesce(data ->> 'farmName', data ->> 'name', '') into v_farm from public.users where uid = v_uid;
  insert into public.truck_hire (uid, farm_name, kind, load_kg, cold_chain, from_place, to_place, km, needed_on, notes, estimate)
  values (v_uid, coalesce(v_farm, ''), p_kind, p_load_kg, p_cold or p_kind = 'refrigerated', trim(p_from), trim(p_to), p_km, p_needed_on, coalesce(p_notes, ''),
          public.truck_estimate(p_kind, p_km, p_cold))
  returning id into v_id;
  select staff_email into v_email from public.notify_config where id = 1;
  perform public.queue_alert('truck', v_email, 'Truck hire request: ' || p_kind, coalesce(v_farm, 'A farm') || ' needs a ' || p_kind || ' for ' || p_load_kg || ' kg, ' || trim(p_from) || ' to ' || trim(p_to) || ' (' || p_km || ' km) on ' || p_needed_on || '.');
  return v_id;
end $$;

create or replace function public.quote_truck(p_id text, p_quote numeric) returns void
language plpgsql security definer set search_path = public as $$
declare t public.truck_hire;
begin
  if not (public.is_hub_staff() or public.is_admin()) then raise exception 'staff only' using errcode = '42501'; end if;
  if p_quote is null or p_quote <= 0 then raise exception 'Give a price.' using errcode = 'P0001'; end if;
  update public.truck_hire set quote = round(p_quote, 2), status = 'quoted', updated_at = now()
   where id = p_id and status in ('requested', 'quoted') returning * into t;
  if not found then raise exception 'That request cannot be quoted now.' using errcode = 'P0001'; end if;
  perform public.notify_user(t.uid, 'truck', 'Your truck quote is ready', 'R' || to_char(t.quote, 'FM999990') || ' for ' || t.from_place || ' to ' || t.to_place || '. Open Sell to accept it.', jsonb_build_object('truck', t.id));
end $$;

create or replace function public.accept_truck(p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.truck_hire;
begin
  update public.truck_hire set status = 'booked', updated_at = now()
   where id = p_id and uid = auth.uid()::text and status = 'quoted' returning * into t;
  if not found then raise exception 'There is no quote to accept.' using errcode = 'P0001'; end if;
  perform public.notify_user(t.uid, 'truck', 'Truck booked', 'Your truck is booked for ' || t.needed_on || '.', jsonb_build_object('truck', t.id));
end $$;

create or replace function public.cancel_truck(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.truck_hire set status = 'cancelled', updated_at = now()
   where id = p_id and uid = auth.uid()::text and status in ('requested', 'quoted', 'booked');
end $$;

create or replace function public.finish_truck(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_hub_staff() or public.is_admin()) then raise exception 'staff only' using errcode = '42501'; end if;
  update public.truck_hire set status = 'done', updated_at = now() where id = p_id and status = 'booked';
end $$;
grant execute on function public.request_truck(text, int, boolean, text, text, numeric, date, text), public.quote_truck(text, numeric),
  public.accept_truck(text), public.cancel_truck(text), public.finish_truck(text) to authenticated;

-- ───────── Realtime ─────────
do $$
declare t text;
begin
  foreach t in array array['notifications', 'driver_locations', 'room_climate', 'truck_hire', 'farm_applications', 'driver_applications',
                           'approved_drivers', 'memberships', 'seller_plans', 'borehole_requests', 'driver_payouts', 'water_zones'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ───────── The three doors ─────────
create schema if not exists drop_api;
create schema if not exists grow_api;
create schema if not exists delivery_api;

-- Drop: farms and what each has in stock.
create or replace function drop_api.farms() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(f order by f ->> 'farm'), '[]'::jsonb) from (
    select jsonb_build_object(
      'ownerId', p.owner_id,
      'farm', max(p.data ->> 'farm'),
      'products', count(*),
      'inStock', count(*) filter (where coalesce((p.data ->> 'stock')::numeric, 1) > 0 and coalesce((p.data ->> 'available')::boolean, true)),
      'items', jsonb_agg(jsonb_build_object('id', p.id, 'name', p.data ->> 'name', 'price', p.data -> 'price', 'unit', p.data ->> 'unit',
                                            'stock', p.data -> 'stock', 'emoji', p.data ->> 'emoji') order by p.data ->> 'name')) as f
      from public.market_products p
     group by p.owner_id) s
$$;

-- Drop (and the seller and the driver): where an order is, live.
create or replace function drop_api.track_order(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.market_orders; l public.driver_locations; v_uid text := auth.uid()::text;
begin
  select * into o from public.market_orders where id = p_id;
  if not found then return null; end if;
  if not (v_uid in (o.customer_id, o.farmer_id, o.driver_id) or public.is_hub_staff() or public.is_admin()) then
    raise exception 'That is not your order.' using errcode = '42501';
  end if;
  if o.driver_id is not null then select * into l from public.driver_locations where driver_id = o.driver_id; end if;
  return jsonb_build_object(
    'id', o.id, 'status', o.status, 'hubStage', o.hub_stage,
    'pickup', o.data ->> 'pickup', 'drop', o.data ->> 'dropArea',
    'pickupProof', coalesce((o.data ->> 'pickupProof')::boolean, false),
    'driver', case when o.driver_id is null then null else jsonb_build_object(
        'name', o.data ->> 'driver', 'lat', l.lat, 'lng', l.lng, 'heading', l.heading, 'speedKmh', l.speed_kmh,
        'online', coalesce(l.online, false), 'updatedAt', case when l.updated_at is null then null else (extract(epoch from l.updated_at) * 1000)::bigint end) end);
end $$;

-- Grow: my products with what the warehouse holds, and how cold the room is.
create or replace function grow_api.my_inventory() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.data ->> 'name', 'emoji', p.data ->> 'emoji', 'unit', p.data ->> 'unit',
    'price', p.data -> 'price', 'shopStock', p.data -> 'stock', 'available', coalesce((p.data ->> 'available')::boolean, true),
    'warehouse', (
      select jsonb_build_object(
        'remaining', coalesce(sum((l.data ->> 'remaining')::numeric), 0),
        'lots', count(*),
        'nextUseBy', min((l.data ->> 'useBy')::bigint),
        'zone', min(l.data ->> 'zone'),
        'tempC', (select c.c from public.room_climate c where c.zone = min(l.data ->> 'zone') and c.hub = coalesce(min(l.data ->> 'hub'), 'Durban hub') limit 1),
        'ok', (select c.ok from public.room_climate c where c.zone = min(l.data ->> 'zone') and c.hub = coalesce(min(l.data ->> 'hub'), 'Durban hub') limit 1))
        from public.warehouse_lots l
       where l.farmer_id = auth.uid()::text and l.data ->> 'status' = 'stored' and (l.data ->> 'remaining')::numeric > 0
         and lower(trim(l.data ->> 'product')) = lower(trim(p.data ->> 'name')))
  ) order by p.data ->> 'name'), '[]'::jsonb)
    from public.market_products p where p.owner_id = auth.uid()::text
$$;

create or replace function grow_api.my_trucks() returns setof public.truck_hire
language sql stable security definer set search_path = public as $$
  select * from public.truck_hire where uid = auth.uid()::text order by created_at desc
$$;
create or replace function grow_api.request_truck(p_kind text, p_load_kg int, p_cold boolean, p_from text, p_to text,
    p_km numeric, p_needed_on date, p_notes text default '') returns text
language sql security definer set search_path = public as $$
  select public.request_truck(p_kind, p_load_kg, p_cold, p_from, p_to, p_km, p_needed_on, p_notes)
$$;
create or replace function grow_api.accept_truck(p_id text) returns void language sql security definer set search_path = public as $$ select public.accept_truck(p_id) $$;
create or replace function grow_api.cancel_truck(p_id text) returns void language sql security definer set search_path = public as $$ select public.cancel_truck(p_id) $$;
create or replace function grow_api.truck_estimate(p_kind text, p_km numeric, p_cold boolean) returns numeric
language sql immutable as $$ select public.truck_estimate(p_kind, p_km, p_cold) $$;
create or replace function grow_api.my_notifications(p_limit int default 50) returns setof public.notifications
language sql stable security definer set search_path = public as $$
  select * from public.notifications where uid = auth.uid()::text order by id desc limit least(coalesce(p_limit, 50), 200)
$$;

-- Delivery: share where I am, and what I am owed.
create or replace function delivery_api.post_location(p_lat double precision, p_lng double precision,
    p_heading real default null, p_speed real default null, p_accuracy real default null) returns void
language sql security definer set search_path = public as $$
  select public.post_location(p_lat, p_lng, p_heading, p_speed, p_accuracy)
$$;
create or replace function delivery_api.go_offline() returns void language sql security definer set search_path = public as $$ select public.go_offline() $$;
create or replace function delivery_api.my_payouts() returns setof public.driver_payouts
language sql stable security definer set search_path = public as $$
  select * from public.driver_payouts where driver_id = auth.uid()::text order by created_at desc limit 200
$$;

-- Only signed-in people use the doors.
revoke all on schema drop_api, grow_api, delivery_api from public, anon;
grant usage on schema drop_api, grow_api, delivery_api to authenticated;
revoke all on all functions in schema drop_api, grow_api, delivery_api from public, anon;
grant execute on all functions in schema drop_api, grow_api, delivery_api to authenticated;
