-- Security fixes from the war room: the server now checks the PIN, the prices
-- and the plan, drivers must be approved, user emails are private, and a person
-- can delete their account.

-- ───────── Plans: only staff decide what a farm pays ─────────
create table public.seller_plans (
  uid text primary key,
  plan text not null default 'starter' check (plan in ('starter', 'grow', 'coop')),
  updated_at timestamptz not null default now()
);
alter table public.seller_plans enable row level security;
create policy seller_plans_read on public.seller_plans for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

create or replace function public.set_seller_plan(p_uid text, p_plan text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  insert into public.seller_plans (uid, plan) values (p_uid, p_plan)
  on conflict (uid) do update set plan = excluded.plan, updated_at = now();
end $$;

create or replace function public.commission_for(p_uid text) returns numeric
language sql stable security definer set search_path = public as $$
  select case coalesce((select plan from public.seller_plans where uid = p_uid), 'starter')
    when 'coop' then 0.03 when 'grow' then 0.05 else 0.08 end
$$;

-- ───────── Drivers must be approved ─────────
create table public.driver_applications (
  uid text primary key,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'needs_info', 'approved', 'rejected')),
  data jsonb not null default '{}',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by text,
  review_note text not null default '',
  updated_at timestamptz not null default now()
);
create table public.approved_drivers (uid text primary key, approved_at timestamptz not null default now());
alter table public.driver_applications enable row level security;
alter table public.approved_drivers enable row level security;
create policy driver_apps_read on public.driver_applications for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());
create policy approved_drivers_self on public.approved_drivers for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

create or replace function public.is_approved_driver() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.approved_drivers where uid = auth.uid()::text)
$$;

create or replace function public.save_driver_application(p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text; cur public.driver_applications;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  select * into cur from public.driver_applications where uid = v_uid;
  if found and cur.status in ('submitted', 'approved') then
    raise exception 'This application is already with Nolifa.' using errcode = 'P0001';
  end if;
  insert into public.driver_applications (uid, data) values (v_uid, p_data)
  on conflict (uid) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.submit_driver_application() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  a public.driver_applications;
  missing text[] := '{}';
  k text;
begin
  select * into a from public.driver_applications where uid = v_uid;
  if not found then raise exception 'Fill in the form first.'; end if;
  if a.status in ('submitted', 'approved') then raise exception 'Already with Nolifa.' using errcode = 'P0001'; end if;
  foreach k in array array['fullName', 'idNumber', 'phone', 'vehicle', 'plate', 'licenceCode', 'consent'] loop
    if coalesce(a.data ->> k, '') in ('', 'null', 'false') then missing := missing || k; end if;
  end loop;
  foreach k in array array['driver_id_front', 'driver_selfie_with_id', 'driver_licence', 'driver_vehicle'] loop
    if not exists (select 1 from public.application_files where uid = v_uid and kind = k) then missing := missing || ('photo:' || k); end if;
  end loop;
  if cardinality(missing) > 0 then
    raise exception 'Still missing: %', array_to_string(missing, ', ') using errcode = 'P0004';
  end if;
  update public.driver_applications set status = 'submitted', submitted_at = now(), updated_at = now(), review_note = '' where uid = v_uid;
end $$;

create or replace function public.review_driver_application(p_uid text, p_decision text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  if p_decision not in ('approved', 'rejected', 'needs_info') then raise exception 'unknown decision'; end if;
  if p_decision <> 'approved' and coalesce(p_note, '') = '' then raise exception 'Say why, so the driver knows what to fix.'; end if;
  update public.driver_applications
     set status = p_decision, reviewed_at = now(), reviewed_by = auth.uid()::text, review_note = coalesce(p_note, ''), updated_at = now()
   where uid = p_uid and status = 'submitted';
  if not found then raise exception 'That application is not waiting for review.'; end if;
  if p_decision = 'approved' then
    insert into public.approved_drivers (uid) values (p_uid) on conflict do nothing;
  else
    delete from public.approved_drivers where uid = p_uid;
  end if;
end $$;

-- Photo files for the driver application live beside the farm ones.
create or replace function public.add_application_file(p_kind text, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if (storage.foldername(p_path))[1] <> v_uid then raise exception 'not your file' using errcode = '42501'; end if;
  delete from public.application_files where uid = v_uid and kind = p_kind and p_kind not in ('certificate', 'land_photo');
  insert into public.application_files (uid, kind, path) values (v_uid, p_kind, p_path);
end $$;

-- Only an approved driver sees open jobs or claims them.
drop policy orders_read on public.market_orders;
create policy orders_read on public.market_orders for select to authenticated using (
  auth.uid()::text = any (participants)
  or (status = 'findingDriver' and driver_id is null and (hub_stage is null or hub_stage = 'released') and public.is_approved_driver())
  or (public.is_hub_staff() and route = 'hub')
  or public.is_mediator());
drop policy orders_update on public.market_orders;
create policy orders_update on public.market_orders for update to authenticated using (
  auth.uid()::text = any (participants)
  or (status = 'findingDriver' and driver_id is null and (hub_stage is null or hub_stage = 'released') and public.is_approved_driver())
  or (public.is_hub_staff() and route = 'hub')
  or public.is_mediator()) with check (true);

create or replace function public.claim_job(p_id text, p_name text) returns boolean
language plpgsql as $$
declare
  uid text := auth.uid()::text;
  d jsonb;
begin
  if not public.is_approved_driver() then
    raise exception 'Only approved drivers can take jobs.' using errcode = '42501';
  end if;
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

create or replace function public.claim_batch(p_ids text[], p_name text) returns boolean
language plpgsql as $$
declare
  v_uid text := auth.uid()::text;
  n int;
begin
  if not public.is_approved_driver() then
    raise exception 'Only approved drivers can take jobs.' using errcode = '42501';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 30 then
    raise exception 'A batch holds 1 to 30 jobs.';
  end if;
  perform 1 from public.market_orders where id = any (p_ids) order by id for update;
  select count(*) into n from public.market_orders
   where id = any (p_ids)
     and data ->> 'status' = 'findingDriver'
     and public.jnull(data, 'driverId')
     and (data ->> 'hubStage' is null or data ->> 'hubStage' = 'released');
  if n <> cardinality(p_ids) then return false; end if;
  update public.market_orders
     set data = data || jsonb_build_object(
       'driverId', v_uid, 'driver', p_name, 'status', 'assigned',
       'rev', coalesce((data ->> 'rev')::int, 0) + 1,
       'participants', coalesce(data -> 'participants', '[]'::jsonb) || to_jsonb(v_uid))
   where id = any (p_ids);
  return true;
end $$;

-- ───────── The PIN lives on the server ─────────
create table public.order_pins (
  order_id text primary key,
  pin_hash text not null,
  attempts int not null default 0
);
alter table public.order_pins enable row level security; -- no policies: only the functions below touch it

-- A buyer places an order. The server checks every price against the real
-- product, works out the service fee itself, and sets the commission from the
-- farm's plan. The delivery fee is checked against the range the fee rules allow.
create or replace function public.place_order(p_data jsonb, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid text := auth.uid()::text;
  v_id text := p_data ->> 'id';
  ln jsonb;
  prod public.market_products;
  owner text;
  sub numeric := 0;
  qty int;
  svc numeric;
  fee numeric := coalesce((p_data ->> 'deliveryFee')::numeric, -1);
  v_route text := coalesce(p_data ->> 'route', 'local');
  self_del boolean := coalesce((p_data ->> 'selfDelivery')::boolean, false);
  farm_fee numeric;
  stage text := p_data ->> 'hubStage';
  from_stock boolean := coalesce((p_data ->> 'fromStock')::boolean, false);
  clean jsonb;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if v_id is null or length(v_id) < 2 then raise exception 'That order has no id.'; end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then raise exception 'The delivery PIN is 4 digits.'; end if;
  if exists (select 1 from public.market_orders where id = v_id) then raise exception 'That order already exists.' using errcode = '23505'; end if;
  if p_data ->> 'customerId' <> v_uid then raise exception 'You can only place orders as yourself.' using errcode = '42501'; end if;
  if jsonb_typeof(p_data -> 'lines') <> 'array' or jsonb_array_length(p_data -> 'lines') not between 1 and 40 then
    raise exception 'An order needs 1 to 40 lines.';
  end if;

  for ln in select * from jsonb_array_elements(p_data -> 'lines') loop
    select * into prod from public.market_products where id = ln ->> 'productId';
    if not found then raise exception 'One of those products is not for sale any more.'; end if;
    if owner is not null and owner <> prod.owner_id then raise exception 'One order can only hold one farm''s products.'; end if;
    owner := prod.owner_id;
    qty := coalesce((ln ->> 'qty')::int, 0);
    if qty < 1 or qty > 1000 then raise exception 'Check the quantity.'; end if;
    if abs(coalesce((ln ->> 'price')::numeric, -1) - (prod.data ->> 'price')::numeric) > 0.005 then
      raise exception 'The price of % changed. Open the shop again.', prod.data ->> 'name' using errcode = 'P0005';
    end if;
    if not public.jnull(prod.data, 'stock') and qty > (prod.data ->> 'stock')::int then
      raise exception 'Only % of % left.', prod.data ->> 'stock', prod.data ->> 'name' using errcode = 'P0005';
    end if;
    if coalesce((prod.data ->> 'available')::boolean, true) = false then
      raise exception '% is paused by the farm.', prod.data ->> 'name' using errcode = 'P0005';
    end if;
    sub := sub + (ln ->> 'price')::numeric * qty;
  end loop;

  if p_data ->> 'farmerId' is distinct from owner then raise exception 'The farm does not match the products.' using errcode = '42501'; end if;

  svc := case when sub <= 0 then 0 else round(least(15, greatest(2, sub * 0.03)), 2) end;
  if abs(coalesce((p_data ->> 'serviceFee')::numeric, -1) - svc) > 0.011 then
    raise exception 'The service fee is wrong. Open the cart again.' using errcode = 'P0005';
  end if;

  if self_del then
    farm_fee := coalesce((select (state -> 'profile' ->> 'deliveryFee')::numeric from public.market_profiles where uid = owner), 0);
    if fee < 0 or fee > 100 or abs(fee - farm_fee) > 0.011 then
      raise exception 'The delivery fee does not match the farm''s own fee.' using errcode = 'P0005';
    end if;
  elsif v_route = 'hub' then
    if fee < 35 or fee > 135 then raise exception 'The delivery fee is outside the hub delivery range.' using errcode = 'P0005'; end if;
  elsif v_route = 'local' then
    if fee < 15 or fee > 65 then raise exception 'The delivery fee is outside the local delivery range.' using errcode = 'P0005'; end if;
  else
    raise exception 'Unknown delivery route.';
  end if;

  if v_route = 'hub' then
    if stage not in ('toHub', 'received') or (stage = 'received' and not from_stock) then raise exception 'Bad hub stage.'; end if;
  elsif stage is not null then
    raise exception 'Bad hub stage.';
  end if;
  if p_data ->> 'status' not in ('newOrder', 'findingDriver') then raise exception 'Bad starting status.'; end if;
  if p_data ->> 'status' = 'findingDriver' and owner <> v_uid then raise exception 'A farm has to pack the order first.' using errcode = '42501'; end if;

  -- What the server sets itself. Fees were checked above and are kept as sent, so
  -- a later update from the buyer's phone matches what is stored.
  clean := p_data || jsonb_build_object(
    'pinHash', 'server', 'released', false, 'dispute', null, 'driverId', null, 'driver', null,
    'pinAttempts', 0, 'rev', 0,
    'participants', case when v_uid = owner then jsonb_build_array(v_uid) else jsonb_build_array(v_uid, owner) end);
  insert into public.market_orders (id, data) values (v_id, clean);
  insert into public.order_pins (order_id, pin_hash) values (v_id, crypt(p_pin, gen_salt('bf', 8)));
end $$;

-- Checks the PIN the customer gives the driver. Three wrong tries lock the
-- order into a dispute. The right PIN marks it delivered.
create or replace function public.deliver_with_pin(p_id text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid text := auth.uid()::text;
  d jsonb;
  pin public.order_pins;
  used int;
begin
  select data into d from public.market_orders where id = p_id for update;
  if d is null then raise exception 'no such order'; end if;
  if not (d ->> 'driverId' = v_uid
          or (d ->> 'farmerId' = v_uid and coalesce((d ->> 'selfDelivery')::boolean, false))) then
    raise exception 'This is not your delivery.' using errcode = '42501';
  end if;
  if d ->> 'status' <> 'pickedUp' then raise exception 'Collect the goods first.' using errcode = 'P0001'; end if;
  if not public.jnull(d, 'dispute') then return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0); end if;
  select * into pin from public.order_pins where order_id = p_id for update;
  if not found or pin.attempts >= 3 then return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0); end if;

  perform set_config('nolifa.internal', '1', true);
  if crypt(p_pin, pin.pin_hash) = pin.pin_hash then
    update public.market_orders set data = d || jsonb_build_object(
      'status', 'delivered', 'deliveredAt', public.now_ms(), 'rev', coalesce((d ->> 'rev')::int, 0) + 1) where id = p_id;
    perform set_config('nolifa.internal', '', true);
    return jsonb_build_object('outcome', 'delivered', 'attemptsLeft', 3);
  end if;
  used := pin.attempts + 1;
  update public.order_pins set attempts = used where order_id = p_id;
  if used >= 3 then
    update public.market_orders set data = d || jsonb_build_object(
      'pinAttempts', used, 'rev', coalesce((d ->> 'rev')::int, 0) + 1,
      'dispute', jsonb_build_object('reason', 'pinLocked', 'stage', 'open', 'outcome', null,
        'note', 'The delivery PIN was entered wrongly 3 times, so the order was locked.',
        'timeline', jsonb_build_array(jsonb_build_object('t', 'The delivery PIN was entered wrongly 3 times, so the order was locked.', 'at', public.now_ms()))))
    where id = p_id;
    perform set_config('nolifa.internal', '', true);
    return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0);
  end if;
  update public.market_orders set data = d || jsonb_build_object('pinAttempts', used, 'rev', coalesce((d ->> 'rev')::int, 0) + 1) where id = p_id;
  perform set_config('nolifa.internal', '', true);
  return jsonb_build_object('outcome', 'wrong', 'attemptsLeft', 3 - used);
end $$;

-- Orders are only created by place_order. put_order only moves existing ones on.
drop policy orders_create on public.market_orders;
create or replace function public.put_order(p_data jsonb) returns void
language plpgsql as $$
declare
  cur_rev int;
  new_rev int := coalesce((p_data ->> 'rev')::int, 0);
begin
  select coalesce((data ->> 'rev')::int, -1) into cur_rev from public.market_orders where id = p_data ->> 'id';
  if not found then raise exception 'Orders are placed with place_order.' using errcode = '42501'; end if;
  if cur_rev >= new_rev then return; end if;
  update public.market_orders set data = p_data where id = p_data ->> 'id';
end $$;

-- The guard: the driver can no longer mark delivered or count PIN tries by hand.
create or replace function public.market_orders_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uid text := auth.uid()::text;
  o jsonb := old.data;
  n jsonb := new.data;
  ch text[] := public.changed_keys(old.data, new.data);
  money text[] := array['lines','deliveryFee','serviceFee','customerId','farmerId','pinHash','method','id'];
  o_stage text := coalesce(o ->> 'hubStage', '');
  ok boolean := false;
begin
  if uid is null or current_setting('nolifa.internal', true) = '1' then return new; end if;
  if ch && money then raise exception 'order money cannot change'; end if;

  if old.farmer_id = uid and o ->> 'status' = 'newOrder' and n ->> 'status' = 'findingDriver'
     and (n ->> 'commission')::numeric = public.commission_for(uid)
     and ch <@ array['status','commission','rev'] then ok := true; end if;

  if not ok and old.farmer_id = uid and o_stage = 'toHub' and o ->> 'status' = 'findingDriver'
     and n ->> 'hubStage' = 'droppedOff' and ch <@ array['hubStage','rev'] then ok := true; end if;

  if not ok and public.is_hub_staff() and o ->> 'status' = 'findingDriver'
     and ((o_stage = 'droppedOff' and n ->> 'hubStage' = 'received')
       or (o_stage = 'received' and n ->> 'hubStage' = 'released'))
     and ch <@ array['hubStage','rev'] then ok := true; end if;

  if not ok and public.is_approved_driver() and o ->> 'status' = 'findingDriver' and public.jnull(o, 'driverId')
     and (o_stage = '' or o_stage = 'released')
     and n ->> 'driverId' = uid and n ->> 'status' = 'assigned'
     and uid = any (new.participants)
     and ch <@ array['status','driver','driverId','participants','rev'] then ok := true; end if;

  -- The driver collects with a photo. Delivery is only through deliver_with_pin.
  if not ok and old.driver_id = uid and public.jnull(o, 'dispute')
     and o ->> 'status' = 'assigned' and n ->> 'status' = 'pickedUp' and n -> 'pickupProof' = 'true'::jsonb
     and ch <@ array['status','pickupProof','rev'] then ok := true; end if;

  if not ok and old.customer_id = uid and o ->> 'status' = 'delivered' and public.jnull(o, 'dispute')
     and o -> 'released' = 'false'::jsonb and n -> 'released' = 'true'::jsonb
     and ch <@ array['released','rating','rev'] then ok := true; end if;

  if not ok and old.customer_id = uid and o -> 'released' = 'false'::jsonb and public.jnull(o, 'dispute')
     and o ->> 'status' in ('pickedUp','delivered')
     and n -> 'dispute' ->> 'stage' = 'open' and public.jnull(n -> 'dispute', 'outcome')
     and ch <@ array['dispute','rev'] then ok := true; end if;

  if not ok and uid = any (old.participants) and o ->> 'status' = 'delivered' and public.jnull(o, 'dispute')
     and o -> 'released' = 'false'::jsonb and n -> 'released' = 'true'::jsonb
     and public.now_ms() >= (o ->> 'deliveredAt')::bigint + 7200000
     and ch <@ array['released','rev'] then ok := true; end if;

  if not ok and public.is_mediator() and not public.jnull(o, 'dispute')
     and ch <@ array['dispute','released','rev'] then ok := true; end if;

  if not ok then raise exception 'that order change is not allowed' using errcode = '42501'; end if;
  return new;
end $$;

-- ───────── Private by default ─────────
drop policy users_read on public.users;
create policy users_read on public.users for select to authenticated using (uid = auth.uid()::text);

-- Outbreak sightings and chat need a verified person, so bots cannot flood them.
drop policy outbreaks_add on public.outbreaks;
create policy outbreaks_add on public.outbreaks for insert to authenticated with check (
  public.is_verified()
  and jsonb_typeof(data -> 'lat') = 'number' and jsonb_typeof(data -> 'lng') = 'number'
  and data ->> 'severity' in ('green','orange','red'));

-- ───────── Delete my account ─────────
create policy consult_videos_del on storage.objects for delete to authenticated
  using (bucket_id = 'consult-videos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy verification_del on storage.objects;
create policy verification_del on storage.objects for delete to authenticated
  using (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if exists (select 1 from public.market_orders
              where v_uid = any (participants)
                and data ->> 'status' <> 'delivered'
                and not (data ->> 'released')::boolean
                and public.jnull(data, 'dispute')) then
    raise exception 'You still have orders in progress. Finish or wait for them, then delete your account.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.market_orders
              where v_uid = any (participants) and not public.jnull(data, 'dispute')
                and data -> 'dispute' ->> 'stage' <> 'resolved') then
    raise exception 'You have an open dispute. It has to be settled first.' using errcode = 'P0001';
  end if;

  -- Orders are kept for accounting, with the person taken out of them.
  perform set_config('nolifa.internal', '1', true);
  update public.market_orders
     set data = data || jsonb_build_object('customer', 'Deleted user', 'dropArea', 'Removed')
   where data ->> 'customerId' = v_uid;
  update public.market_orders set data = data || jsonb_build_object('driver', 'Deleted driver') where data ->> 'driverId' = v_uid;
  perform set_config('nolifa.internal', '', true);

  delete from public.cattle where uid = v_uid;
  delete from public.health_log where uid = v_uid;
  delete from public.care_log where uid = v_uid;
  delete from public.water_prefs where uid = v_uid;
  delete from public.water_votes where uid = v_uid;
  delete from public.chat_messages where uid = v_uid;
  delete from public.consult_messages where sender = v_uid;
  delete from public.consults where farmer_id = v_uid;
  delete from public.market_products where owner_id = v_uid;
  delete from public.market_cases where reporter_id = v_uid;
  delete from public.warehouse_lots where farmer_id = v_uid and data ->> 'status' = 'expected';
  update public.borehole_requests set address = '', contact_phone = '', notes = '' where uid = v_uid;
  delete from public.application_files where uid = v_uid;
  delete from public.farm_applications where uid = v_uid;
  delete from public.farm_profiles where uid = v_uid;
  delete from public.driver_applications where uid = v_uid;
  delete from public.approved_drivers where uid = v_uid;
  delete from public.memberships where uid = v_uid;
  delete from public.seller_plans where uid = v_uid;
  delete from public.verified_users where uid = v_uid;
  delete from public.market_profiles where uid = v_uid;
  delete from public.users where uid = v_uid;
  delete from auth.users where id = auth.uid();
end $$;

alter publication supabase_realtime add table public.seller_plans, public.driver_applications, public.approved_drivers;

-- Tells the app, before it deletes any files, whether deletion can go ahead.
create or replace function public.delete_blocker() returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.market_orders
                  where auth.uid()::text = any (participants)
                    and data ->> 'status' <> 'delivered'
                    and not (data ->> 'released')::boolean
                    and public.jnull(data, 'dispute'))
      then 'You still have orders in progress. Finish or wait for them, then delete your account.'
    when exists (select 1 from public.market_orders
                  where auth.uid()::text = any (participants) and not public.jnull(data, 'dispute')
                    and data -> 'dispute' ->> 'stage' <> 'resolved')
      then 'You have an open dispute. It has to be settled first.'
  end
$$;
