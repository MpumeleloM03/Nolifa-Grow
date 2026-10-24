begin;
select * from no_plan();

create function pg_temp.as_user(p_uid text, p_session text, p_meta jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_session, 'app_metadata', p_meta)::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end $$;

\set adm '''a0000000-0000-0000-0000-000000000001'''
\set vet '''a0000000-0000-0000-0000-000000000002'''
\set farmer '''a0000000-0000-0000-0000-000000000003'''
\set test '''a0000000-0000-0000-0000-000000000004'''

insert into auth.users (id, email) values
  (:adm::uuid, 'owner@example.com'), (:vet::uuid, 'vet@example.com'),
  (:farmer::uuid, 'farmer@example.com'), (:test::uuid, 'test@example.com');
insert into public.admins (uid) values (:adm);

-- switched off: nothing changes ---------------------------------------------------------
select pg_temp.as_user(:adm, 's-admin-1');
select is(public.is_admin(), true, 'with the switch off an admin is an admin');
select is((public.second_factor_status() ->> 'required')::boolean, false, 'and no code is needed');

-- switched on ------------------------------------------------------------------------------
select lives_ok($f$select public.set_staff_2fa(true)$f$, 'an admin turns the second factor on');
select is(public.is_admin(), false, 'a session with no code is no longer an admin');
select is((public.second_factor_status() ->> 'required')::boolean, true, 'the app is told a code is needed');
select throws_ok($f$select public.set_staff_2fa(false)$f$, '42501', null, 'and cannot flip the switch without a code');

select is(public.request_login_code() ->> 'sentTo', 'o***@example.com', 'a code is sent, and the address is masked');
select pg_temp.as_admin();
select is((select count(*)::int from public.outbox where kind = 'login_code' and to_email = 'owner@example.com'), 1, 'it is queued for the right address');
select ok((select body ~ 'sign-in code is [0-9]{6}' from public.outbox where kind = 'login_code' limit 1), 'the email holds a 6-digit code');
create temp table code as select substring(body from 'code is ([0-9]{6})') as c from public.outbox where kind = 'login_code' limit 1;
grant select on code to authenticated;

select pg_temp.as_user(:adm, 's-admin-1');
select throws_ok($f$select public.request_login_code()$f$, 'P0001', null, 'a second code cannot be asked for straight away');
select is(public.verify_login_code('000000'), false, 'a wrong code is refused');
select is(public.is_admin(), false, 'and opens nothing');
select is(public.verify_login_code((select c from code)), true, 'the right code is accepted');
select is(public.is_admin(), true, 'the session is now an admin');
select is(public.verify_login_code((select c from code)), false, 'a code works once');

select pg_temp.as_user(:adm, 's-admin-2');
select is(public.is_admin(), false, 'another sign-in session has to ask again');

-- tries run out ------------------------------------------------------------------------------------
select pg_temp.as_admin();
update public.login_codes set code_hash = extensions.crypt('123456', extensions.gen_salt('bf', 4)), expires_at = now() + interval '5 minutes' where uid = :adm;
insert into public.login_codes (uid, code_hash, expires_at) values (:adm, extensions.crypt('123456', extensions.gen_salt('bf', 4)), now() + interval '5 minutes') on conflict (uid) do update set tries = 0;
select pg_temp.as_user(:adm, 's-admin-2');
select is(public.verify_login_code('1'), false, 'wrong 1');
select is(public.verify_login_code('2'), false, 'wrong 2');
select is(public.verify_login_code('3'), false, 'wrong 3');
select is(public.verify_login_code('4'), false, 'wrong 4');
select is(public.verify_login_code('5'), false, 'wrong 5');
select throws_ok($f$select public.verify_login_code('123456')$f$, 'P0001', null, 'after 5 wrong tries even the right code is refused');

-- expired ------------------------------------------------------------------------------------------------
select pg_temp.as_admin();
update public.login_codes set tries = 0, expires_at = now() - interval '1 minute' where uid = :adm;
select pg_temp.as_user(:adm, 's-admin-2');
select is(public.verify_login_code('123456'), false, 'an expired code is refused');

-- other roles ------------------------------------------------------------------------------------------------
select pg_temp.as_user(:vet, 's-vet', '{"vet": true}');
select is(public.is_vet(), false, 'a vet needs a code too');
select pg_temp.as_user(:farmer, 's-farmer');
select is((public.second_factor_status() ->> 'required')::boolean, false, 'a farmer is never asked');
select is(public.request_login_code() ->> 'required', 'false', 'and cannot trigger an email');
select pg_temp.as_user(:test, 's-test', '{"utility": true}');
select is(public.is_utility(), false, 'a water provider needs a code');
select pg_temp.as_user(:adm, 's-admin-1');
select lives_ok(format($f$select public.exempt_from_2fa(%L, 'mailbox cannot receive mail yet')$f$, :test), 'an admin can exempt a test account, with a reason');
select throws_ok(format($f$select public.exempt_from_2fa(%L, '')$f$, :test), 'P0001', null, 'a reason is required');
select pg_temp.as_user(:test, 's-test', '{"utility": true}');
select is(public.is_utility(), true, 'the exempt account works without a code');
select pg_temp.as_user(:farmer, 's-farmer');
select throws_ok(format($f$select public.exempt_from_2fa(%L, 'x')$f$, :farmer), '42501', null, 'a farmer cannot exempt anyone');

-- the code never shows in the back office ------------------------------------------------------------------
select pg_temp.as_user(:adm, 's-admin-1');
select is((select count(*)::int from public.outbox where kind = 'login_code'), 0, 'the back office outbox hides sign-in codes');

select * from finish();
rollback;
