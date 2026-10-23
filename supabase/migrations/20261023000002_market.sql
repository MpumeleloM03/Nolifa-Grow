-- Nolifa Drop marketplace: products, orders (with the state machine the old
-- Firestore rules enforced), outbreak cases and community sightings.

create table public.market_products (
  id text primary key,
  owner_id text not null,
  data jsonb not null
);
alter table public.market_products enable row level security;

create or replace function public.valid_stock(p jsonb) returns boolean
language sql immutable as $$
  select public.jnull(p, 'stock')
    or (jsonb_typeof(p -> 'stock') = 'number' and (p ->> 'stock')::numeric = floor((p ->> 'stock')::numeric)
        and (p ->> 'stock')::numeric between 0 and 100000)
$$;

create or replace function public.valid_product(p jsonb) returns boolean
language sql immutable as $$
  select jsonb_typeof(p -> 'name') = 'string' and length(p ->> 'name') between 1 and 80
    and jsonb_typeof(p -> 'price') = 'number' and (p ->> 'price')::numeric > 0 and (p ->> 'price')::numeric <= 100000
    and public.valid_stock(p)
    and (p -> 'available' is null or jsonb_typeof(p -> 'available') = 'boolean')
$$;

create policy products_read on public.market_products for select to authenticated using (true);
create policy products_insert on public.market_products for insert to authenticated
  with check (owner_id = auth.uid()::text and data ->> 'ownerId' = auth.uid()::text and public.valid_product(data));
create policy products_update on public.market_products for update to authenticated
  using (owner_id = auth.uid()::text)
  with check (owner_id = auth.uid()::text and data ->> 'ownerId' = auth.uid()::text and public.valid_product(data));
create policy products_delete on public.market_products for delete to authenticated using (owner_id = auth.uid()::text);

-- Orders
create table public.market_orders (
  id text primary key,
  data jsonb not null,
  customer_id text,
  farmer_id text,
  driver_id text,
  status text,
  route text,
  hub_stage text,
  participants text[] not null default '{}'
);
create index market_orders_participants on public.market_orders using gin (participants);
alter table public.market_orders enable row level security;

create or replace function public.market_orders_cols() returns trigger
language plpgsql as $$
begin
  new.id := coalesce(new.data ->> 'id', new.id);
  new.customer_id := new.data ->> 'customerId';
  new.farmer_id := new.data ->> 'farmerId';
  new.driver_id := new.data ->> 'driverId';
  new.status := new.data ->> 'status';
  new.route := new.data ->> 'route';
  new.hub_stage := new.data ->> 'hubStage';
  new.participants := coalesce(
    (select array_agg(p) from jsonb_array_elements_text(
       case when jsonb_typeof(new.data -> 'participants') = 'array' then new.data -> 'participants' else '[]'::jsonb end) p),
    '{}');
  return new;
end $$;
create trigger a_market_orders_cols before insert or update on public.market_orders
  for each row execute function public.market_orders_cols();

create or replace function public.commission_for(p_uid text) returns numeric
language sql stable security definer set search_path = public as $$
  select case coalesce((select state ->> 'plan' from public.market_profiles where uid = p_uid), '')
    when 'coop' then 0.03 when 'grow' then 0.05 else 0.08 end
$$;

create or replace function public.order_is_open(o public.market_orders) returns boolean
language sql immutable as $$
  select o.status = 'findingDriver' and o.driver_id is null
    and (o.hub_stage is null or o.hub_stage = 'released')
$$;

create policy orders_read on public.market_orders for select to authenticated using (
  auth.uid()::text = any (participants)
  or (status = 'findingDriver' and driver_id is null and (hub_stage is null or hub_stage = 'released'))
  or (public.is_hub_staff() and route = 'hub')
  or public.is_mediator());

create policy orders_create on public.market_orders for insert to authenticated with check (
  customer_id = auth.uid()::text
  and status in ('newOrder', 'findingDriver')
  and data -> 'released' = 'false'::jsonb
  and public.jnull(data, 'dispute')
  and driver_id is null
  and jsonb_typeof(data -> 'lines') = 'array'
  and jsonb_array_length(data -> 'lines') between 1 and 40
  and jsonb_typeof(data -> 'deliveryFee') = 'number'
  and jsonb_typeof(data -> 'serviceFee') = 'number'
  and jsonb_typeof(data -> 'pinHash') = 'string'
  and (hub_stage is null or hub_stage in ('toHub', 'received'))
  and auth.uid()::text = any (participants));

create policy orders_update on public.market_orders for update to authenticated using (
  auth.uid()::text = any (participants)
  or (status = 'findingDriver' and driver_id is null and (hub_stage is null or hub_stage = 'released'))
  or (public.is_hub_staff() and route = 'hub')
  or public.is_mediator()) with check (true);

-- Every change to an order has to match exactly one of the allowed steps.
create or replace function public.market_orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uid text := auth.uid()::text;
  o jsonb := old.data;
  n jsonb := new.data;
  ch text[] := public.changed_keys(old.data, new.data);
  money text[] := array['lines','deliveryFee','serviceFee','customerId','farmerId','pinHash','method','id'];
  o_stage text := coalesce(o ->> 'hubStage', '');
  attempts int := coalesce((o ->> 'pinAttempts')::int, 0);
  ok boolean := false;
begin
  -- Trusted backend (service role / SQL console) is not restricted.
  if uid is null then return new; end if;
  if ch && money then raise exception 'order money cannot change'; end if;

  -- The farmer packs a new order, locking in the commission for their plan.
  if old.farmer_id = uid and o ->> 'status' = 'newOrder' and n ->> 'status' = 'findingDriver'
     and (n ->> 'commission')::numeric = public.commission_for(uid)
     and ch <@ array['status','commission','rev'] then ok := true; end if;

  -- The farm says a hub order has been dropped at the hub.
  if not ok and old.farmer_id = uid and o_stage = 'toHub' and o ->> 'status' = 'findingDriver'
     and n ->> 'hubStage' = 'droppedOff' and ch <@ array['hubStage','rev'] then ok := true; end if;

  -- Hub staff check an order in, then release it to last-mile drivers.
  if not ok and public.is_hub_staff() and o ->> 'status' = 'findingDriver'
     and ((o_stage = 'droppedOff' and n ->> 'hubStage' = 'received')
       or (o_stage = 'received' and n ->> 'hubStage' = 'released'))
     and ch <@ array['hubStage','rev'] then ok := true; end if;

  -- A driver claims an open job for themselves.
  if not ok and o ->> 'status' = 'findingDriver' and public.jnull(o, 'driverId')
     and (o_stage = '' or o_stage = 'released')
     and n ->> 'driverId' = uid and n ->> 'status' = 'assigned'
     and uid = any (new.participants)
     and ch <@ array['status','driver','driverId','participants','rev'] then ok := true; end if;

  -- The assigned driver collects (with a photo), then delivers.
  if not ok and old.driver_id = uid and public.jnull(o, 'dispute') and (
       (o ->> 'status' = 'assigned' and n ->> 'status' = 'pickedUp' and n -> 'pickupProof' = 'true'::jsonb
         and ch <@ array['status','pickupProof','rev'])
    or (o ->> 'status' = 'pickedUp' and n ->> 'status' = 'delivered'
         and ch <@ array['status','deliveredAt','rev'])) then ok := true; end if;

  -- A wrong delivery PIN counts as a try; the third locks the order into a dispute.
  if not ok and old.driver_id = uid and o ->> 'status' = 'pickedUp' and public.jnull(o, 'dispute') then
    if attempts < 2 and (n ->> 'pinAttempts')::int = attempts + 1 and ch <@ array['pinAttempts','rev'] then ok := true; end if;
    if attempts = 2 and (n ->> 'pinAttempts')::int = 3
       and n -> 'dispute' ->> 'reason' = 'pinLocked' and n -> 'dispute' ->> 'stage' = 'open'
       and public.jnull(n -> 'dispute', 'outcome')
       and ch <@ array['pinAttempts','dispute','rev'] then ok := true; end if;
  end if;

  -- The buyer confirms receipt (releasing payment) and rates.
  if not ok and old.customer_id = uid and o ->> 'status' = 'delivered' and public.jnull(o, 'dispute')
     and o -> 'released' = 'false'::jsonb and n -> 'released' = 'true'::jsonb
     and ch <@ array['released','rating','rev'] then ok := true; end if;

  -- The buyer opens a dispute, freezing payment until a mediator rules.
  if not ok and old.customer_id = uid and o -> 'released' = 'false'::jsonb and public.jnull(o, 'dispute')
     and o ->> 'status' in ('pickedUp','delivered')
     and n -> 'dispute' ->> 'stage' = 'open' and public.jnull(n -> 'dispute', 'outcome')
     and ch <@ array['dispute','rev'] then ok := true; end if;

  -- Anyone on the order can release payment 2 hours after delivery.
  if not ok and uid = any (old.participants) and o ->> 'status' = 'delivered' and public.jnull(o, 'dispute')
     and o -> 'released' = 'false'::jsonb and n -> 'released' = 'true'::jsonb
     and public.now_ms() >= (o ->> 'deliveredAt')::bigint + 7200000
     and ch <@ array['released','rev'] then ok := true; end if;

  -- Only a mediator rules on a dispute.
  if not ok and public.is_mediator() and not public.jnull(o, 'dispute')
     and ch <@ array['dispute','released','rev'] then ok := true; end if;

  if not ok then raise exception 'that order change is not allowed' using errcode = '42501'; end if;
  return new;
end $$;
create trigger b_market_orders_guard before update on public.market_orders
  for each row execute function public.market_orders_guard();

-- Save an order only if this copy is newer than what is stored.
create or replace function public.put_order(p_data jsonb) returns void
language plpgsql as $$
declare
  cur_rev int;
  new_rev int := coalesce((p_data ->> 'rev')::int, 0);
begin
  select coalesce((data ->> 'rev')::int, -1) into cur_rev from public.market_orders where id = p_data ->> 'id';
  if found then
    if cur_rev >= new_rev then return; end if;
    update public.market_orders set data = p_data where id = p_data ->> 'id';
  else
    insert into public.market_orders (id, data) values (p_data ->> 'id', p_data);
  end if;
end $$;

-- A driver takes an open job; only one driver can win.
create or replace function public.claim_job(p_id text, p_name text) returns boolean
language plpgsql as $$
declare
  uid text := auth.uid()::text;
  d jsonb;
begin
  select data into d from public.market_orders where id = p_id for update;
  if d is null or not public.jnull(d, 'driverId') or d ->> 'status' <> 'findingDriver'
     or (d ->> 'hubStage' is not null and d ->> 'hubStage' <> 'released') then
    return false;
  end if;
  update public.market_orders set data = d || jsonb_build_object(
      'driverId', uid, 'driver', p_name, 'status', 'assigned',
      'rev', coalesce((d ->> 'rev')::int, 0) + 1,
      'participants', coalesce(d -> 'participants', '[]'::jsonb) || to_jsonb(uid))
    where id = p_id;
  return true;
end $$;

-- Outbreak cases
create table public.market_cases (
  id text primary key,
  data jsonb not null,
  reporter_id text
);
alter table public.market_cases enable row level security;
create or replace function public.market_cases_cols() returns trigger language plpgsql as $$
begin new.reporter_id := new.data ->> 'reporterId'; return new; end $$;
create trigger a_market_cases_cols before insert or update on public.market_cases
  for each row execute function public.market_cases_cols();

create policy cases_read on public.market_cases for select to authenticated using (true);
create policy cases_create on public.market_cases for insert to authenticated with check (
  reporter_id = auth.uid()::text
  and data ->> 'stage' = 'aiChecked'
  and (data ->> 'confirmations')::int = 0
  and jsonb_typeof(data -> 'title') = 'string' and length(data ->> 'title') between 1 and 120);
create policy cases_vet on public.market_cases for update to authenticated
  using (public.is_vet()) with check (public.is_vet());

create or replace function public.market_cases_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or current_setting('nolifa.internal', true) = '1' then return new; end if;
  if public.changed_keys(old.data, new.data) <@ array['confirmations','confirmedBy','stage']
     and new.data ->> 'stage' in ('vetVerified','rejected') then return new; end if;
  raise exception 'that case change is not allowed' using errcode = '42501';
end $$;
create trigger b_market_cases_guard before update on public.market_cases
  for each row execute function public.market_cases_guard();

-- A different verified neighbour confirms a case once.
create or replace function public.confirm_case(p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid text := auth.uid()::text;
  d jsonb;
  who jsonb;
  stage text;
begin
  if not public.is_verified() then raise exception 'only verified people can confirm' using errcode = '42501'; end if;
  select data into d from public.market_cases where id = p_id for update;
  if d is null or d ->> 'reporterId' = uid then return; end if;
  who := coalesce(d -> 'confirmedBy', '[]'::jsonb);
  if who ? uid then return; end if;
  who := who || to_jsonb(uid);
  stage := d ->> 'stage';
  if jsonb_array_length(who) >= 2 and stage = 'aiChecked' then stage := 'corroborated'; end if;
  perform set_config('nolifa.internal', '1', true);
  update public.market_cases set data = d || jsonb_build_object(
    'confirmedBy', who, 'confirmations', jsonb_array_length(who), 'stage', stage) where id = p_id;
  perform set_config('nolifa.internal', '', true);
end $$;

-- Community disease sightings: append only.
create table public.outbreaks (
  id text primary key default gen_random_uuid()::text,
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.outbreaks enable row level security;
create policy outbreaks_read on public.outbreaks for select to authenticated using (true);
create policy outbreaks_add on public.outbreaks for insert to authenticated with check (
  jsonb_typeof(data -> 'lat') = 'number' and jsonb_typeof(data -> 'lng') = 'number'
  and data ->> 'severity' in ('green','orange','red'));

-- Hub staff and farms move a hub order one step; the guard decides if it is allowed.
create or replace function public.set_hub_stage(p_id text, p_stage text) returns void
language plpgsql as $$
begin
  update public.market_orders
     set data = data || jsonb_build_object('hubStage', p_stage, 'rev', coalesce((data ->> 'rev')::int, 0) + 1)
   where id = p_id;
end $$;
