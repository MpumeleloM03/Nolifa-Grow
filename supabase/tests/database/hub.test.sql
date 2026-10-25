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
create function pg_temp.hub_order(p_id text, p_stage text, p_cust text, p_farm text) returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'customerId', p_cust, 'farmerId', p_farm, 'status', 'findingDriver',
    'released', false, 'dispute', null, 'driverId', null, 'hubStage', p_stage, 'route', 'hub',
    'lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Spinach', 'qty', 1, 'price', 20, 'ownerId', p_farm)),
    'deliveryFee', 35, 'serviceFee', 2, 'pinHash', 'abc', 'method', 'cash',
    'participants', jsonb_build_array(p_cust, p_farm), 'rev', 0)
$$;

\set buyer '''b0000000-0000-0000-0000-000000000001'''
\set farmer '''f0000000-0000-0000-0000-000000000002'''
\set d1 '''d0000000-0000-0000-0000-000000000003'''
\set other '''e0000000-0000-0000-0000-000000000005'''
\set hub '''a0000000-0000-0000-0000-000000000006'''

insert into public.staff (uid) values (:hub);
insert into public.approved_drivers (uid) values (:d1);
insert into public.market_products (id, owner_id, data) values ('P1', :farmer, jsonb_build_object('ownerId', :farmer, 'name', 'Spinach', 'price', 20, 'stock', 50));

select pg_temp.as_user(:buyer);
select lives_ok(format($f$select public.place_order(%L || '{"status":"newOrder"}'::jsonb, '1234')$f$, pg_temp.hub_order('H1', 'toHub', :buyer, :farmer)),
  'a hub order starts on the way to the hub');
select pg_temp.as_user(:farmer);
select lives_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.08,"rev":1}' where id = 'H1'$f$, 'the farm packs it');
select pg_temp.as_user(:buyer);

-- nobody can take it while it is at the hub
select pg_temp.as_user(:d1);
select is((select count(*)::int from public.market_orders where id = 'H1'), 0, 'a driver cannot see an order that is not released');
select is(public.claim_job('H1', 'Driver'), false, 'a driver cannot take an order still at the hub');

select pg_temp.as_user(:other);
select lives_ok($f$update public.market_orders set data = data || '{"hubStage":"droppedOff","rev":1}' where id = 'H1'$f$, 'a stranger update is silently ignored');
select pg_temp.as_admin();
select is((select data ->> 'hubStage' from public.market_orders where id = 'H1'), 'toHub', 'a stranger cannot mark it dropped off');
select pg_temp.as_user(:buyer);
select pg_temp.as_user(:buyer);
select throws_ok($f$select public.set_hub_stage('H1', 'droppedOff')$f$, '42501', null, 'the buyer cannot say the farm dropped it off');
select pg_temp.as_user(:farmer);
select lives_ok($f$select public.set_hub_stage('H1', 'droppedOff')$f$, 'the selling farm says it dropped it off');

select pg_temp.as_user(:hub);
select is((select count(*)::int from public.market_orders where id = 'H1'), 1, 'hub staff see hub orders');
select throws_ok($f$select public.set_hub_stage('H1', 'released')$f$, '42501', null, 'staff cannot skip check in');
select lives_ok($f$select public.set_hub_stage('H1', 'received')$f$, 'staff check it in');
select lives_ok($f$select public.set_hub_stage('H1', 'released')$f$, 'staff release it to drivers');

select pg_temp.as_user(:d1);
select is((select count(*)::int from public.market_orders where id = 'H1'), 1, 'a released order is an open job');
select is(public.claim_job('H1', 'Driver'), true, 'now a driver can take it');

-- a non staff person cannot read hub orders they are not in
select pg_temp.as_admin();
insert into public.market_orders (id, data) values ('H2', pg_temp.hub_order('H2', 'received', :buyer, :farmer));
select pg_temp.as_user(:other);
select is((select count(*)::int from public.market_orders where id = 'H2'), 0, 'a stranger cannot read hub orders');
select pg_temp.as_user(:hub);
select is((select count(*)::int from public.market_orders where id = 'H2'), 1, 'staff can');

select * from finish();
rollback;
