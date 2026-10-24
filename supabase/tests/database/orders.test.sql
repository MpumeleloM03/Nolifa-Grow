begin;
select * from no_plan();

create function pg_temp.as_user(p_uid text, p_meta jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'app_metadata', p_meta)::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end $$;
-- A buyer's order as the app sends it: price 80, service fee 2.40, delivery 25.
create function pg_temp.order_json(p_id text, p_cust text, p_farm text, p_extra jsonb default '{}') returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'customerId', p_cust, 'farmerId', p_farm, 'status', 'newOrder',
    'lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Eggs', 'qty', 1, 'price', 80, 'ownerId', p_farm)),
    'deliveryFee', 25, 'serviceFee', 2.4, 'method', 'fnbPay', 'route', 'local', 'customer', 'Buyer', 'dropArea', 'Street',
    'participants', jsonb_build_array(p_cust, p_farm), 'rev', 0) || p_extra
$$;
-- An order already in a later state, put there by the server side for the test.
create function pg_temp.seed_order(p_id text, p_cust text, p_farm text, p_extra jsonb) returns void language plpgsql as $$
begin
  insert into public.market_orders (id, data) values (p_id,
    pg_temp.order_json(p_id, p_cust, p_farm) || jsonb_build_object('released', false, 'dispute', null, 'driverId', null, 'pinHash', 'server') || p_extra);
  insert into public.order_pins (order_id, pin_hash) values (p_id, extensions.crypt('4321', extensions.gen_salt('bf', 4)));
end $$;

\set buyer '''b0000000-0000-0000-0000-000000000001'''
\set farmer '''f0000000-0000-0000-0000-000000000002'''
\set d1 '''d0000000-0000-0000-0000-000000000003'''
\set d2 '''d0000000-0000-0000-0000-000000000004'''
\set stranger '''e0000000-0000-0000-0000-000000000005'''
\set med '''c0000000-0000-0000-0000-000000000007'''
\set adm '''c0000000-0000-0000-0000-000000000008'''

insert into public.seller_plans (uid, plan) values (:farmer, 'grow');
insert into public.market_products (id, owner_id, data) values ('P1', :farmer, jsonb_build_object('ownerId', :farmer, 'name', 'Eggs', 'price', 80, 'stock', 5));
insert into public.approved_drivers (uid) values (:d1), (:d2);
insert into public.admins (uid) values (:adm);

-- placing an order ----------------------------------------------------------------
select pg_temp.as_user(:buyer);
select lives_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O1', :buyer, :farmer)), 'a buyer places an order');
select is((select data ->> 'pinHash' from public.market_orders where id = 'O1'), 'server', 'the PIN hash is not stored in the order');
select is((select count(*)::int from public.order_pins), 0, 'and nobody can read the PIN table');
select is((select data ->> 'released' from public.market_orders where id = 'O1'), 'false', 'the server sets the money state itself');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O2', %L)$f$, pg_temp.order_json('O2', :buyer, :farmer)),
  '42501', null, 'no direct inserts: orders only come through place_order');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O1', :buyer, :farmer)), '23505', null, 'the same order cannot be placed twice');
select throws_ok(format($f$select public.place_order(%L, '12')$f$, pg_temp.order_json('O3', :buyer, :farmer)), 'P0001', null, 'the PIN must be 4 digits');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$,
  pg_temp.order_json('O4', :buyer, :farmer, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Eggs', 'qty', 1, 'price', 1, 'ownerId', :farmer))))),
  'P0005', null, 'a cheaper price than the product is refused');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O5', :buyer, :farmer, '{"serviceFee": 0}')), 'P0005', null, 'a wrong service fee is refused');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O6', :buyer, :farmer, '{"deliveryFee": 0}')), 'P0005', null, 'a R0 delivery fee is refused');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O7', :buyer, :farmer, '{"deliveryFee": 999}')), 'P0005', null, 'a huge delivery fee is refused');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$,
  pg_temp.order_json('O8', :buyer, :farmer, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Eggs', 'qty', 9, 'price', 80, 'ownerId', :farmer))))),
  'P0005', null, 'more than the stock is refused');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O9', :stranger, :farmer)), '42501', null, 'cannot order as someone else');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O10', :buyer, :farmer, '{"status":"findingDriver"}')), '42501', null, 'cannot skip the farm''s packing');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O11', :buyer, :stranger)), '42501', null, 'the farm must own the products');
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O12', :buyer, :farmer, '{"route":"hub","deliveryFee":35,"hubStage":"released"}')), 'P0001', null, 'a hub order cannot start released');
select lives_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('O13', :buyer, :farmer, '{"route":"hub","deliveryFee":35,"hubStage":"toHub"}')), 'a hub order starts on the way to the hub');

-- privacy and money ------------------------------------------------------------------
select pg_temp.as_user(:stranger);
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'a stranger cannot see it');
select pg_temp.as_user(:buyer);
select throws_ok($f$update public.market_orders set data = data || '{"deliveryFee": 1}' where id = 'O1'$f$, null, null, 'the buyer cannot change the fee afterwards');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.03,"rev":1}' where id = 'O1'$f$, '42501', null, 'a lower commission than the plan is refused');
select pg_temp.as_admin();
update public.market_profiles set state = '{"plan":"coop"}' where uid = :farmer;
insert into public.market_profiles (uid, state) values (:farmer, '{"plan":"coop"}') on conflict (uid) do update set state = excluded.state;
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.03,"rev":1}' where id = 'O1'$f$, '42501', null, 'writing coop into your own profile does not lower commission');
select lives_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.05,"rev":1}' where id = 'O1'$f$, 'the farmer packs with the commission staff set');
select pg_temp.as_user(:farmer);
select throws_ok($f$select public.set_seller_plan('f0000000-0000-0000-0000-000000000002', 'coop')$f$, '42501', null, 'a farmer cannot change their own plan');
select pg_temp.as_user(:adm);
select lives_ok($f$select public.set_seller_plan('f0000000-0000-0000-0000-000000000002', 'coop')$f$, 'an admin can');

-- only approved drivers ------------------------------------------------------------------
select pg_temp.as_user(:stranger);
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'an unapproved person cannot see open jobs');
select throws_ok($f$select public.claim_job('O1', 'Nobody')$f$, '42501', null, 'or take them');
select pg_temp.as_user(:d1);
select is((select count(*)::int from public.market_orders where id = 'O1'), 1, 'an approved driver sees the open job');
select is(public.claim_job('O1', 'Driver One'), true, 'and takes it');
select pg_temp.as_user(:d2);
select is(public.claim_job('O1', 'Driver Two'), false, 'a second driver does not');
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'it vanishes for other drivers');

-- pickup, then the PIN is checked by the server -----------------------------------------------
select pg_temp.as_user(:d1);
select throws_ok($f$update public.market_orders set data = data || '{"status":"pickedUp","rev":3}' where id = 'O1'$f$, '42501', null, 'pickup needs the photo proof');
select lives_ok($f$update public.market_orders set data = data || '{"status":"pickedUp","pickupProof":true,"rev":3}' where id = 'O1'$f$, 'the driver collects with a photo');
select throws_ok($f$update public.market_orders set data = data || '{"status":"delivered","deliveredAt":1,"rev":4}' where id = 'O1'$f$, '42501', null, 'the driver cannot mark delivered by hand');
select throws_ok($f$update public.market_orders set data = data || '{"pinAttempts":0,"rev":4}' where id = 'O1'$f$, '42501', null, 'or touch the try counter');
select is((public.deliver_with_pin('O1', '0000') ->> 'outcome'), 'wrong', 'a wrong PIN is wrong');
select is((public.deliver_with_pin('O1', '1111') ->> 'attemptsLeft')::int, 1, 'with one try left after two');
select is((public.deliver_with_pin('O1', '2222') ->> 'outcome'), 'locked', 'the third wrong PIN locks the order');
select is((select data -> 'dispute' ->> 'reason' from public.market_orders where id = 'O1'), 'pinLocked', 'and opens a dispute');
select is((public.deliver_with_pin('O1', '4321') ->> 'outcome'), 'locked', 'even the right PIN no longer works once locked');

select pg_temp.as_admin();
select pg_temp.seed_order('O20', :buyer, :farmer, jsonb_build_object('status', 'pickedUp', 'driverId', :d1, 'participants', jsonb_build_array(:buyer, :farmer, :d1), 'pickupProof', true));
select pg_temp.as_user(:d2);
select throws_ok($f$select public.deliver_with_pin('O20', '4321')$f$, '42501', null, 'another driver cannot deliver it');
select pg_temp.as_user(:buyer);
select throws_ok($f$select public.deliver_with_pin('O20', '4321')$f$, '42501', null, 'neither can the buyer');
select pg_temp.as_user(:d1);
select is((public.deliver_with_pin('O20', '4321') ->> 'outcome'), 'delivered', 'the right PIN delivers it');
select is((select data ->> 'status' from public.market_orders where id = 'O20'), 'delivered', 'and the order says so');
select ok((select (data ->> 'deliveredAt')::bigint > 0 from public.market_orders where id = 'O20'), 'with a time');

-- a farm that delivers itself uses the same PIN check -------------------------------------------------
select pg_temp.as_admin();
select pg_temp.seed_order('O21', :buyer, :farmer, jsonb_build_object('status', 'pickedUp', 'selfDelivery', true, 'participants', jsonb_build_array(:buyer, :farmer)));
select pg_temp.as_user(:farmer);
select is((public.deliver_with_pin('O21', '4321') ->> 'outcome'), 'delivered', 'a farm delivering its own order uses the PIN too');

-- buyer confirms, two hour release, dispute, mediator --------------------------------------------------
select pg_temp.as_admin();
select pg_temp.seed_order('O22', :buyer, :farmer, jsonb_build_object('status', 'delivered', 'driverId', :d1, 'deliveredAt', public.now_ms(), 'participants', jsonb_build_array(:buyer, :farmer, :d1)));
select pg_temp.seed_order('O23', :buyer, :farmer, jsonb_build_object('status', 'delivered', 'driverId', :d1, 'deliveredAt', public.now_ms() - 7300000, 'participants', jsonb_build_array(:buyer, :farmer, :d1)));
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"released":true,"rev":2}' where id = 'O22'$f$, '42501', null, 'the farmer cannot release payment straight away');
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"released":true,"rating":5,"rev":2}' where id = 'O22'$f$, 'the buyer confirms receipt');
select pg_temp.as_user(:farmer);
select lives_ok($f$update public.market_orders set data = data || '{"released":true,"rev":2}' where id = 'O23'$f$, 'after two hours anyone on the order can release');
select pg_temp.as_admin();
select pg_temp.seed_order('O24', :buyer, :farmer, jsonb_build_object('status', 'delivered', 'driverId', :d1, 'deliveredAt', public.now_ms(), 'participants', jsonb_build_array(:buyer, :farmer, :d1)));
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"missing","stage":"open","outcome":null},"rev":2}' where id = 'O24'$f$, 'the buyer opens a dispute');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"released":true,"rev":3}' where id = 'O24'$f$, '42501', null, 'a disputed order cannot be released');
select pg_temp.as_user(:stranger);
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"missing","stage":"resolved","outcome":"fullRefund"},"released":true,"rev":3}' where id = 'O24'$f$, 'a stranger ruling is ignored');
select pg_temp.as_admin();
select is((select data -> 'dispute' ->> 'stage' from public.market_orders where id = 'O24'), 'open', 'nothing changed');
select pg_temp.as_user(:med, '{"mediator": true}');
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"missing","stage":"resolved","outcome":"fullRefund"},"released":true,"rev":3}' where id = 'O24'$f$, 'a mediator rules');

-- put_order only moves existing orders on --------------------------------------------------------------
select pg_temp.as_user(:buyer);
select throws_ok(format($f$select public.put_order(%L)$f$, pg_temp.order_json('O30', :buyer, :farmer, '{"rev": 5}')), '42501', null, 'put_order cannot create an order');
select lives_ok(format($f$select public.put_order(%L)$f$, pg_temp.order_json('O13', :buyer, :farmer, '{"rev": 0}')), 'an old copy is ignored');

select * from finish();
rollback;
