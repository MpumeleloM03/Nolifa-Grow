-- Card payments for orders, and stock that the server keeps.
--
--  * A new order starts unpaid (cash on delivery starts paid). A seller cannot pack
--    or dispatch it until Yoco's signed message says it is paid.
--  * The amount is worked out here from the order itself, never from the phone.
--  * Stock comes off the shelf on the server, at the moment of ordering, under a
--    row lock, so two buyers cannot take the last kilo and a closed farmer app
--    cannot leave the shop showing stock that is gone.

alter table public.payments add column if not exists order_id text;
create index if not exists payments_order on public.payments (order_id);

-- What an order costs, in cents: items + delivery + service fee.
create or replace function public.order_amount_cents(p_id text) returns int
language sql stable security definer set search_path = public as $$
  select (round((coalesce((select sum((l ->> 'price')::numeric * (l ->> 'qty')::numeric)
                             from jsonb_array_elements(d -> 'lines') l), 0)
                 + coalesce((d ->> 'deliveryFee')::numeric, 0) + coalesce((d ->> 'serviceFee')::numeric, 0)) * 100))::int
    from (select data as d from public.market_orders where id = p_id) o
$$;
revoke all on function public.order_amount_cents(text) from public, anon, authenticated;
grant execute on function public.order_amount_cents(text) to service_role;

-- Only the server (service role) may mark an order paid.
create or replace function public.activate_order_paid(p_payment text, p_checkout text) returns text
language plpgsql security definer set search_path = public as $$
declare p public.payments; o public.market_orders;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from public.payments where id = p_payment and checkout_id = p_checkout and kind = 'order' for update;
  if not found then return 'unknown'; end if;
  if p.status = 'paid' then return 'already'; end if;
  select * into o from public.market_orders where id = p.order_id for update;
  if not found then return 'no order'; end if;
  update public.payments set status = 'paid', paid_at = now() where id = p.id;
  perform set_config('nolifa.internal', '1', true);
  update public.market_orders
     set data = data || jsonb_build_object('paid', true, 'paidAt', public.now_ms(), 'rev', coalesce((data ->> 'rev')::int, 0) + 1)
   where id = o.id;
  perform set_config('nolifa.internal', '', true);
  perform public.notify_user(o.farmer_id, 'order_paid', 'Order ' || right(o.id, 5) || ' is paid', 'Pack it and scan the parcel to send it out.', jsonb_build_object('order', o.id));
  perform public.notify_user(o.customer_id, 'order_paid', 'Payment received', 'Your money is held safely until you confirm delivery.', jsonb_build_object('order', o.id));
  return 'paid';
end $$;
revoke all on function public.activate_order_paid(text, text) from public, anon, authenticated;
grant execute on function public.activate_order_paid(text, text) to service_role;

-- A phone cannot say an order is paid, or change that it is not. This runs first
-- (the name sorts before the other guards) and puts the server's own keys back, so a
-- full-document update from an older copy on a phone does not look like a change.
create or replace function public.order_paid_guard() returns trigger language plpgsql as $$
declare k text;
begin
  if auth.uid() is null or current_setting('nolifa.internal', true) = '1' then return new; end if;
  foreach k in array array['paid', 'paidAt', 'stockTaken'] loop
    if old.data ? k then
      new.data := jsonb_set(new.data, array[k], old.data -> k);
    else
      new.data := new.data - k;
    end if;
  end loop;
  -- An unpaid card order cannot move on.
  if old.data ->> 'status' = 'newOrder' and new.data ->> 'status' is distinct from 'newOrder'
     and coalesce((old.data ->> 'paid')::boolean, true) = false and old.data ->> 'method' <> 'cash' then
    raise exception 'This order is not paid yet.' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists c_order_paid_guard on public.market_orders;
drop trigger if exists a_order_paid_guard on public.market_orders;
create trigger a_order_paid_guard before update on public.market_orders
  for each row execute function public.order_paid_guard();

-- place_order, as before, plus: the paid flag, and stock taken under a lock.
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
    select * into prod from public.market_products where id = ln ->> 'productId' for update;
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

  -- The shelf shrinks now, on the server, so every phone sees the same number.
  perform set_config('nolifa.internal', '1', true);
  for ln in select * from jsonb_array_elements(p_data -> 'lines') loop
    update public.market_products
       set data = jsonb_set(data, '{stock}', to_jsonb((data ->> 'stock')::int - (ln ->> 'qty')::int))
     where id = ln ->> 'productId' and not public.jnull(data, 'stock');
  end loop;
  perform set_config('nolifa.internal', '', true);

  -- What the server sets itself. Fees were checked above and are kept as sent.
  -- Card orders start unpaid; a seller cannot pack them until Yoco confirms.
  clean := p_data || jsonb_build_object(
    'pinHash', 'server', 'released', false, 'dispute', null, 'driverId', null, 'driver', null,
    'pinAttempts', 0, 'rev', 0, 'stockTaken', true,
    'paid', coalesce(p_data ->> 'method', '') = 'cash',
    'participants', case when v_uid = owner then jsonb_build_array(v_uid) else jsonb_build_array(v_uid, owner) end);
  insert into public.market_orders (id, data) values (v_id, clean);
  insert into public.order_pins (order_id, pin_hash) values (v_id, crypt(p_pin, gen_salt('bf', 8)));
end $$;
