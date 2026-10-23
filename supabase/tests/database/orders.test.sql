begin;
select * from no_plan();

-- helpers ---------------------------------------------------------------
create function pg_temp.as_user(p_uid text, p_meta jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'app_metadata', p_meta)::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end $$;
create function pg_temp.order_json(p_id text, p_cust text, p_farm text, p_extra jsonb default '{}') returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'customerId', p_cust, 'farmerId', p_farm, 'status', 'newOrder',
    'released', false, 'dispute', null, 'driverId', null,
    'lines', '[{"name":"Eggs","qty":1,"price":80}]'::jsonb, 'deliveryFee', 25, 'serviceFee', 5,
    'pinHash', 'abc', 'method', 'fnbPay', 'participants', jsonb_build_array(p_cust, p_farm),
    'rev', 0, 'route', 'local') || p_extra
$$;

\set buyer '''b0000000-0000-0000-0000-000000000001'''
\set farmer '''f0000000-0000-0000-0000-000000000002'''
\set d1 '''d0000000-0000-0000-0000-000000000003'''
\set d2 '''d0000000-0000-0000-0000-000000000004'''
\set stranger '''e0000000-0000-0000-0000-000000000005'''
\set hub '''a0000000-0000-0000-0000-000000000006'''
\set med '''c0000000-0000-0000-0000-000000000007'''

insert into public.market_profiles (uid, state) values (:farmer, '{"plan":"grow"}');
insert into public.staff (uid) values (:hub);

-- create -------------------------------------------------------------------
select pg_temp.as_user(:buyer);
select lives_ok(format($f$insert into public.market_orders (id, data) values ('O1', %L)$f$,
  pg_temp.order_json('O1', :buyer, :farmer)), 'a buyer creates their own order');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O2', %L)$f$,
  pg_temp.order_json('O2', :stranger, :farmer, jsonb_build_object('participants', jsonb_build_array(:stranger)))),
  '42501', null, 'a buyer cannot create an order as someone else');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O3', %L)$f$,
  pg_temp.order_json('O3', :buyer, :farmer, '{"released": true}')),
  '42501', null, 'an order cannot start already released');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O4', %L)$f$,
  pg_temp.order_json('O4', :buyer, :farmer, '{"driverId": "x"}')),
  '42501', null, 'an order cannot start with a driver');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O5', %L)$f$,
  pg_temp.order_json('O5', :buyer, :farmer, '{"lines": []}')),
  '42501', null, 'an order needs at least one line');
select throws_ok(format($f$insert into public.market_orders (id, data) values ('O6', %L)$f$,
  pg_temp.order_json('O6', :buyer, :farmer, '{"hubStage": "released"}')),
  '42501', null, 'a hub order cannot start already released');

-- privacy ------------------------------------------------------------------
select is((select count(*)::int from public.market_orders where id = 'O1'), 1, 'buyer sees it');
select pg_temp.as_user(:stranger);
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'a stranger cannot see it');
select pg_temp.as_user(:d1);
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'a driver cannot see an order the farmer has not packed');

-- money is frozen ---------------------------------------------------------
select pg_temp.as_user(:buyer);
select throws_ok($f$update public.market_orders set data = data || '{"deliveryFee": 1}' where id = 'O1'$f$,
  null, null, 'the buyer cannot change the delivery fee');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"serviceFee": 0}' where id = 'O1'$f$,
  null, null, 'the farmer cannot change the service fee');

-- farmer packs --------------------------------------------------------------
select throws_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.01,"rev":1}' where id = 'O1'$f$,
  '42501', null, 'a wrong commission is refused');
select throws_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.05,"rev":1,"released":true}' where id = 'O1'$f$,
  '42501', null, 'packing cannot also release payment');
select lives_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.05,"rev":1}' where id = 'O1'$f$,
  'the farmer packs with the commission for their plan');
select pg_temp.as_user(:buyer);
select throws_ok($f$update public.market_orders set data = data || '{"status":"delivered","rev":9}' where id = 'O1'$f$,
  '42501', null, 'the buyer cannot mark it delivered');

-- driver claims -------------------------------------------------------------
select pg_temp.as_user(:d1);
select is((select count(*)::int from public.market_orders where id = 'O1'), 1, 'an open job is visible to drivers');
select is(public.claim_job('O1', 'Driver One'), true, 'the first driver gets the job');
select pg_temp.as_user(:d2);
select is((select count(*)::int from public.market_orders where id = 'O1'), 0, 'it vanishes for other drivers');
select is(public.claim_job('O1', 'Driver Two'), false, 'the second driver does not');
select pg_temp.as_user(:farmer);
select is((select data ->> 'driver' from public.market_orders where id = 'O1'), 'Driver One', 'the farmer sees who took it');

-- pickup and delivery ----------------------------------------------------------
select pg_temp.as_user(:d2);
select is((select count(*)::int from (select 1 from public.market_orders where id = 'O1') x), 0, 'driver two has no access');
select pg_temp.as_user(:d1);
select throws_ok($f$update public.market_orders set data = data || '{"status":"pickedUp","rev":3}' where id = 'O1'$f$,
  '42501', null, 'pickup needs the photo proof');
select lives_ok($f$update public.market_orders set data = data || '{"status":"pickedUp","pickupProof":true,"rev":3}' where id = 'O1'$f$,
  'the driver collects with a photo');
select lives_ok($f$update public.market_orders set data = data || '{"pinAttempts":1,"rev":4}' where id = 'O1'$f$, 'a wrong PIN counts as a try');
select throws_ok($f$update public.market_orders set data = data || '{"pinAttempts":0,"rev":5}' where id = 'O1'$f$,
  '42501', null, 'tries cannot be reset');
select lives_ok($f$update public.market_orders set data = data || '{"pinAttempts":2,"rev":5}' where id = 'O1'$f$, 'second wrong try');
select throws_ok($f$update public.market_orders set data = data || '{"pinAttempts":3,"rev":6}' where id = 'O1'$f$,
  '42501', null, 'the third wrong try must lock the order');
select lives_ok($f$update public.market_orders set data = data ||
  '{"pinAttempts":3,"rev":6,"dispute":{"reason":"pinLocked","stage":"open","outcome":null}}' where id = 'O1'$f$,
  'the third wrong try locks the order into a dispute');
select throws_ok($f$update public.market_orders set data = data || '{"status":"delivered","deliveredAt":1,"rev":7}' where id = 'O1'$f$,
  '42501', null, 'a locked order cannot be delivered');

-- mediator rules ------------------------------------------------------------------
select pg_temp.as_user(:stranger);
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"pinLocked","stage":"resolved","outcome":"refund"},"released":true,"rev":7}' where id = 'O1'$f$,
  'a stranger update is silently ignored');
select pg_temp.as_admin();
select is((select data -> 'dispute' ->> 'stage' from public.market_orders where id = 'O1'), 'open', 'a stranger cannot rule on a dispute');
select pg_temp.as_user(:med, '{"mediator": true}');
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"pinLocked","stage":"resolved","outcome":"refund"},"released":true,"rev":7}' where id = 'O1'$f$,
  'a mediator rules on the dispute');

-- clean delivery, buyer confirms, and the 2 hour release --------------------------
select pg_temp.as_admin();
insert into public.market_orders (id, data) values
  ('O7', pg_temp.order_json('O7', :buyer, :farmer, jsonb_build_object('status', 'pickedUp', 'driverId', :d1,
     'participants', jsonb_build_array(:buyer, :farmer, :d1), 'pickupProof', true))),
  ('O8', pg_temp.order_json('O8', :buyer, :farmer, jsonb_build_object('status', 'delivered', 'driverId', :d1,
     'participants', jsonb_build_array(:buyer, :farmer, :d1), 'deliveredAt', public.now_ms())));
select pg_temp.as_user(:d1);
select lives_ok(format($f$update public.market_orders set data = data || '{"status":"delivered","deliveredAt":%s,"rev":1}' where id = 'O7'$f$, public.now_ms()),
  'the driver delivers');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"released":true,"rev":2}' where id = 'O7'$f$,
  '42501', null, 'the farmer cannot release payment straight away');
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"released":true,"rating":5,"rev":2}' where id = 'O7'$f$,
  'the buyer confirms receipt and releases payment');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"released":true,"rev":1}' where id = 'O8'$f$,
  '42501', null, 'payment is not auto released inside two hours');
select pg_temp.as_admin();
update public.market_orders set data = data || jsonb_build_object('deliveredAt', public.now_ms() - 7300000) where id = 'O8';
select pg_temp.as_user(:farmer);
select lives_ok($f$update public.market_orders set data = data || '{"released":true,"rev":1}' where id = 'O8'$f$,
  'after two hours with no dispute anyone on the order can release payment');

-- buyer opens a dispute -----------------------------------------------------------
select pg_temp.as_admin();
insert into public.market_orders (id, data) values
  ('O9', pg_temp.order_json('O9', :buyer, :farmer, jsonb_build_object('status', 'delivered', 'driverId', :d1,
     'participants', jsonb_build_array(:buyer, :farmer, :d1), 'deliveredAt', public.now_ms())));
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"dispute":{"reason":"missing","stage":"open","outcome":null},"rev":1}' where id = 'O9'$f$,
  'the buyer opens a dispute');
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"released":true,"rev":2}' where id = 'O9'$f$,
  '42501', null, 'a disputed order cannot be released');

-- put_order keeps the newest copy -------------------------------------------------------
select pg_temp.as_user(:buyer);
select lives_ok(format($f$select public.put_order(%L)$f$, pg_temp.order_json('O10', :buyer, :farmer, '{"rev": 5}')), 'a new order saves');
select lives_ok(format($f$select public.put_order(%L)$f$, pg_temp.order_json('O10', :buyer, :farmer, '{"rev": 4}')), 'an older copy is ignored');
select is((select (data ->> 'rev')::int from public.market_orders where id = 'O10'), 5, 'the newer copy is kept');

select * from finish();
rollback;
