begin;
select * from no_plan();

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
end $$;
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end $$;

\set f '''a5000000-0000-0000-0000-000000000001'''
\set g '''a5000000-0000-0000-0000-000000000002'''

select pg_temp.as_user(:f);
select public.join_membership('max');
select pg_temp.as_admin();
insert into public.payments (id, uid, tier, amount_cents, checkout_id) values ('p1', :f, 'max', 700000, 'ch_1');

select pg_temp.as_user(:f);
select throws_ok($f$select public.activate_membership_paid('p1', 'ch_1')$f$, '42501', null, 'a farmer cannot mark their own payment as paid');
select is((select status from public.payments where id = 'p1'), 'created', 'it stays unpaid');
select is(public.membership_tier(:f), 'none', 'and the membership stays off');
select throws_ok($f$insert into public.payments (uid, tier, amount_cents) values ('a5000000-0000-0000-0000-000000000001', 'max', 1)$f$, '42501', null, 'nobody inserts payments from the app');
select pg_temp.as_user(:g);
select is((select count(*)::int from public.payments), 0, 'another person cannot see the payment');

select pg_temp.as_service();
select is(public.activate_membership_paid('p1', 'wrong'), 'unknown', 'a wrong checkout reference does nothing');
select is(public.membership_tier(:f), 'none', 'the membership is still off');
select is(public.activate_membership_paid('p1', 'ch_1'), 'activated', 'the signed payment turns it on');
select is(public.activate_membership_paid('p1', 'ch_1'), 'already', 'the same message twice does nothing more');
select pg_temp.as_admin();
select is(public.membership_tier(:f), 'max', 'the Max tier is now active');
select is((select (term_ends_at > now() + interval '23 months') from public.memberships where uid = :f), true, 'for 24 months');
select is((select payment_ref from public.memberships where uid = :f), 'yoco:ch_1', 'with the card reference kept');

select * from finish();
rollback;
