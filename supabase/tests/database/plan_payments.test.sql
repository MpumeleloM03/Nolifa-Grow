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

\set farm '''c3000000-0000-0000-0000-000000000001'''
\set other '''c3000000-0000-0000-0000-000000000002'''

select is(public.plan_price_cents('grow'), 9900, 'the server knows the price of Grow');
select is(public.plan_price_cents('free'), null, 'and has no price for a made up plan');

insert into public.payments (id, uid, kind, tier, amount_cents, checkout_id) values ('pay-plan-1', :farm, 'plan', 'grow', 9900, 'co-1');

select pg_temp.as_user(:farm);
select throws_ok($f$select public.activate_plan_paid('pay-plan-1', 'co-1')$f$, '42501', null, 'a farm cannot activate its own plan payment');
select throws_ok($f$select public.set_seller_plan('c3000000-0000-0000-0000-000000000001', 'coop')$f$, '42501', null, 'and cannot set its own plan');
select pg_temp.as_admin();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(public.activate_plan_paid('pay-plan-1', 'wrong'), 'unknown', 'a payment with the wrong checkout is refused');
select is(public.activate_plan_paid('pay-plan-1', 'co-1'), 'activated', 'the signed payment switches the plan on');
select is(public.activate_plan_paid('pay-plan-1', 'co-1'), 'already', 'a repeated message does nothing');
reset role;

select is((select plan from public.seller_plans where uid = :farm), 'grow', 'the plan is Grow');
select is(public.commission_for(:farm), 0.05, 'and the commission follows at once');
select is((select count(*)::int from public.notifications where uid = :farm and kind = 'plan'), 1, 'the farm is told');
select is((select source || ':' || from_plan || '>' || to_plan from public.plan_changes where uid = :farm), 'card:starter>grow', 'the switch is on the record');

select pg_temp.as_user(:other);
select is((select count(*)::int from public.plan_changes), 0, 'another farm cannot see it');
select pg_temp.as_user(:farm);
select is((select count(*)::int from public.plan_changes), 1, 'the farm sees its own');

select * from finish();
rollback;
