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

\set a '''a1000000-0000-0000-0000-000000000001'''
\set b '''b1000000-0000-0000-0000-000000000002'''
\set c '''c1000000-0000-0000-0000-000000000003'''
\set v '''d1000000-0000-0000-0000-000000000004'''

-- private profile --------------------------------------------------------------
select pg_temp.as_user(:a);
select lives_ok($f$insert into public.market_profiles (uid, state) values ('a1000000-0000-0000-0000-000000000001', '{"plan":"free"}')$f$, 'own profile saves');
select throws_ok($f$insert into public.market_profiles (uid, state) values ('b1000000-0000-0000-0000-000000000002', '{}')$f$, '42501', null, 'cannot write another profile');
select pg_temp.as_user(:b);
select is((select count(*)::int from public.market_profiles), 0, 'profiles are private');

-- products ---------------------------------------------------------------------
select pg_temp.as_user(:a);
select lives_ok(format($f$insert into public.market_products (id, owner_id, data) values ('P1', %L, %L)$f$, :a,
  jsonb_build_object('ownerId', :a, 'name', 'Carrots', 'price', 60, 'stock', 20)), 'a farmer lists a product');
select throws_ok(format($f$insert into public.market_products (id, owner_id, data) values ('P2', %L, %L)$f$, :a,
  jsonb_build_object('ownerId', :a, 'name', 'Free', 'price', 0)), '42501', null, 'price must be above zero');
select throws_ok(format($f$insert into public.market_products (id, owner_id, data) values ('P3', %L, %L)$f$, :a,
  jsonb_build_object('ownerId', :a, 'name', 'Stock', 'price', 5, 'stock', -1)), '42501', null, 'stock cannot be negative');
select throws_ok(format($f$insert into public.market_products (id, owner_id, data) values ('P4', %L, %L)$f$, :b,
  jsonb_build_object('ownerId', :b, 'name', 'Mine', 'price', 5)), '42501', null, 'cannot list as someone else');
select pg_temp.as_user(:b);
select is((select count(*)::int from public.market_products), 1, 'everyone signed in can browse');
select lives_ok($f$update public.market_products set data = data || '{"price": 1}' where id = 'P1'$f$, 'a stranger update is ignored');
select lives_ok($f$delete from public.market_products where id = 'P1'$f$, 'a stranger delete is ignored');
select pg_temp.as_admin();
select is((select (data ->> 'price')::int from public.market_products where id = 'P1'), 60, 'a stranger cannot reprice');
select pg_temp.as_user(:a);
select lives_ok($f$update public.market_products set data = data || '{"price": 65, "stock": 10}' where id = 'P1'$f$, 'the owner reprices and restocks');
select is((select data ->> 'price' from public.market_products where id = 'P1'), '65', 'owner change saved');

-- signed out ------------------------------------------------------------------------
select pg_temp.as_admin();
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select lives_ok('set local role anon', 'switch to anon');
select is((select count(*)::int from public.market_products), 0, 'signed out people read nothing');

-- outbreak cases ----------------------------------------------------------------------
select pg_temp.as_admin();
insert into public.verified_users (uid) values (:a), (:b), (:c), (:v);
select pg_temp.as_user(:a);
select lives_ok(format($f$insert into public.market_cases (id, data) values ('C1', %L)$f$,
  jsonb_build_object('reporterId', :a, 'stage', 'aiChecked', 'confirmations', 0, 'confirmedBy', '[]'::jsonb, 'title', 'Foot and mouth')),
  'a farmer files a case');
select throws_ok(format($f$insert into public.market_cases (id, data) values ('C2', %L)$f$,
  jsonb_build_object('reporterId', :a, 'stage', 'vetVerified', 'confirmations', 0, 'title', 'Fake')), '42501', null, 'a case cannot start vet verified');
select throws_ok(format($f$insert into public.market_cases (id, data) values ('C3', %L)$f$,
  jsonb_build_object('reporterId', :b, 'stage', 'aiChecked', 'confirmations', 0, 'title', 'As b')), '42501', null, 'cannot file as someone else');
select lives_ok($f$select public.confirm_case('C1')$f$, 'the reporter confirming their own case does nothing');
select is((select data ->> 'confirmations' from public.market_cases where id = 'C1'), '0', 'own confirmation not counted');
select pg_temp.as_user(:b);
select lives_ok($f$select public.confirm_case('C1')$f$, 'a verified neighbour confirms');
select lives_ok($f$select public.confirm_case('C1')$f$, 'the same neighbour again');
select is((select data ->> 'confirmations' from public.market_cases where id = 'C1'), '1', 'one person counts once');
select pg_temp.as_user(:c);
select lives_ok($f$select public.confirm_case('C1')$f$, 'a second neighbour confirms');
select is((select data ->> 'stage' from public.market_cases where id = 'C1'), 'corroborated', 'two neighbours corroborate it');
select pg_temp.as_user('e1000000-0000-0000-0000-000000000009');
select throws_ok($f$select public.confirm_case('C1')$f$, '42501', null, 'an unverified person cannot confirm');
select lives_ok($f$update public.market_cases set data = data || '{"stage":"vetVerified"}' where id = 'C1'$f$, 'a non vet update is ignored');
select pg_temp.as_user(:v, '{"vet": true}');
select lives_ok($f$update public.market_cases set data = data || '{"stage":"vetVerified"}' where id = 'C1'$f$, 'a vet verifies');
select is((select data ->> 'stage' from public.market_cases where id = 'C1'), 'vetVerified', 'vet verification saved');
select throws_ok($f$update public.market_cases set data = data || '{"title":"Edited"}' where id = 'C1'$f$, '42501', null, 'a vet cannot rewrite the title');

-- outbreaks are append only ----------------------------------------------------------------
select pg_temp.as_user(:a);
select lives_ok($f$insert into public.outbreaks (data) values ('{"lat":-29.5,"lng":30.2,"severity":"red","disease":"x"}')$f$, 'a sighting is added');
select throws_ok($f$insert into public.outbreaks (data) values ('{"lat":-29.5,"lng":30.2,"severity":"purple"}')$f$, '42501', null, 'severity is checked');
select throws_ok($f$insert into public.outbreaks (data) values ('{"lat":"x","lng":30.2,"severity":"red"}')$f$, '42501', null, 'coordinates must be numbers');
select lives_ok($f$update public.outbreaks set data = '{}'$f$, 'edits are ignored (no policy)');
select lives_ok($f$delete from public.outbreaks$f$, 'deletes are ignored (no policy)');
select pg_temp.as_admin();
select is((select count(*)::int from public.outbreaks), 1, 'history is intact');

-- herd and health log are private --------------------------------------------------------------
select pg_temp.as_user(:a);
select lives_ok($f$insert into public.cattle (uid, id, data) values ('a1000000-0000-0000-0000-000000000001', 'c1', '{"tagNumber":"001"}')$f$, 'own animal saves');
select throws_ok($f$insert into public.cattle (uid, id, data) values ('b1000000-0000-0000-0000-000000000002', 'c2', '{}')$f$, '42501', null, 'cannot add to another herd');
select pg_temp.as_user(:b);
select is((select count(*)::int from public.cattle), 0, 'another farmer sees no herd');
select is((select count(*)::int from public.health_log), 0, 'or health log');

-- roles cannot be added by clients ----------------------------------------------------------------
select pg_temp.as_user(:a);
select throws_ok($f$insert into public.staff (uid) values ('a1000000-0000-0000-0000-000000000001')$f$, '42501', null, 'nobody adds themselves as staff');
select throws_ok($f$insert into public.certifiers (uid) values ('a1000000-0000-0000-0000-000000000001')$f$, '42501', null, 'nor as a certifier');
select throws_ok($f$insert into public.verified_users (uid) values ('a1000000-0000-0000-0000-000000000001')$f$, '42501', null, 'nor as verified');

select * from finish();
rollback;
