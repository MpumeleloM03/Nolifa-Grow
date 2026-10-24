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
create function pg_temp.open_order(p_id text, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'customerId', 'cust', 'farmerId', 'farm', 'status', 'findingDriver',
    'released', false, 'dispute', null, 'driverId', null, 'driver', null,
    'lines', '[{"name":"Beef","qty":20,"price":100}]'::jsonb, 'deliveryFee', 40, 'serviceFee', 5,
    'pinHash', 'x', 'method', 'fnbPay', 'participants', '["cust","farm"]'::jsonb, 'rev', 1) || p_extra
$$;

\set d1 '''d2000000-0000-0000-0000-000000000001'''
\set d2 '''d2000000-0000-0000-0000-000000000002'''

insert into public.market_orders (id, data) values
  ('B1', pg_temp.open_order('B1')), ('B2', pg_temp.open_order('B2')), ('B3', pg_temp.open_order('B3')),
  ('B4', pg_temp.open_order('B4', '{"hubStage":"received"}'));

select pg_temp.as_user(:d1);
select is(public.claim_batch(array['B1','B2','B3'], 'Driver One'), true, 'a driver takes three jobs at once');
select is((select count(*)::int from public.market_orders where driver_id = :d1), 3, 'all three are theirs');
select is((select (data ->> 'rev')::int from public.market_orders where id = 'B1'), 2, 'each job moved on one revision');
select pg_temp.as_user(:d2);
select is(public.claim_batch(array['B1','B2'], 'Driver Two'), false, 'a second driver cannot take jobs already taken');
select pg_temp.as_admin();
insert into public.market_orders (id, data) values ('B5', pg_temp.open_order('B5')), ('B6', pg_temp.open_order('B6'));
select pg_temp.as_user(:d2);
select is(public.claim_batch(array['B5','B4'], 'Driver Two'), false, 'a job still at the hub fails the whole batch');
select is((select count(*)::int from public.market_orders where id = 'B5' and driver_id is not null), 0, 'and the free job is left alone');
select is(public.claim_batch(array['B5','B6'], 'Driver Two'), true, 'two free jobs are taken together');
select throws_ok($f$select public.claim_batch(array[]::text[], 'x')$f$, 'P0001', null, 'an empty batch is refused');

select * from finish();
rollback;
