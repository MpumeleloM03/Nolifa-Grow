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
create function pg_temp.hazard(p_rep text, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('kind', 'pothole', 'lat', -29.8, 'lng', 30.9, 'reportedAt', public.now_ms(),
    'lastSeen', public.now_ms(), 'reporter', p_rep, 'reporterName', 'Sipho', 'confirms', jsonb_build_array(p_rep),
    'denies', '[]'::jsonb, 'note', '') || p_extra
$$;

\set a '''ab000000-0000-0000-0000-000000000001'''
\set b '''ab000000-0000-0000-0000-000000000002'''
\set c '''ab000000-0000-0000-0000-000000000003'''
\set nv '''ab000000-0000-0000-0000-000000000004'''
\set hub '''ab000000-0000-0000-0000-000000000005'''
\set cert '''ab000000-0000-0000-0000-000000000006'''

insert into public.verified_users (uid) values (:a), (:b), (:c);
insert into public.staff (uid) values (:hub);
insert into public.certifiers (uid) values (:cert);

-- road hazards --------------------------------------------------------------------------
select pg_temp.as_user(:nv);
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h0', %s, %L)$f$, public.now_ms(), pg_temp.hazard(:nv)),
  '42501', null, 'an unverified person cannot report');
select pg_temp.as_user(:a);
select lives_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h1', %s, %L)$f$, public.now_ms(), pg_temp.hazard(:a)),
  'a verified driver reports a hazard');
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h2', %s, %L)$f$, public.now_ms(), pg_temp.hazard(:a, '{"kind":"volcano"}')),
  '42501', null, 'unknown kinds are refused');
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h3', %s, %L)$f$, public.now_ms(), pg_temp.hazard(:a, '{"lat": 10}')),
  '42501', null, 'outside South Africa is refused');
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h4', %s, %L)$f$, public.now_ms(), pg_temp.hazard(:b)),
  '42501', null, 'cannot report as someone else');
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h5', %s, %L)$f$, public.now_ms() - 3600000,
  pg_temp.hazard(:a, jsonb_build_object('reportedAt', public.now_ms() - 3600000, 'lastSeen', public.now_ms() - 3600000))),
  '42501', null, 'backdated reports are refused');
select throws_ok(format($f$insert into public.road_hazards (id, last_seen, data) values ('h6', %s, %L)$f$, public.now_ms(),
  pg_temp.hazard(:a, jsonb_build_object('confirms', jsonb_build_array(:a, :b)))),
  '42501', null, 'a report cannot start with extra sightings');

select pg_temp.as_user(:b);
select lives_ok(format($f$update public.road_hazards set data = data || jsonb_build_object('confirms', jsonb_build_array(%L, %L), 'lastSeen', public.now_ms()), last_seen = public.now_ms() where id = 'h1'$f$, :a, :b),
  'a second driver says still there');
select throws_ok(format($f$update public.road_hazards set data = data || jsonb_build_object('confirms', jsonb_build_array(%L, %L, %L)) where id = 'h1'$f$, :a, :b, :c),
  '42501', null, 'one person cannot add another person as a sighting');
select throws_ok($f$update public.road_hazards set data = data || '{"lat": -30}' where id = 'h1'$f$, '42501', null, 'the position cannot move');
select lives_ok(format($f$update public.road_hazards set data = data || jsonb_build_object('denies', jsonb_build_array(%L), 'confirms', jsonb_build_array(%L)) where id = 'h1'$f$, :b, :a),
  'a driver says it is gone');
select is((select data -> 'confirms' from public.road_hazards where id = 'h1'), to_jsonb(array[:a]), 'the reporter sighting stays');
select pg_temp.as_user(:nv);
select is((select count(*)::int from public.road_hazards), 1, 'everyone signed in can read warnings');
select lives_ok($f$delete from public.road_hazards$f$, 'delete is ignored');
select pg_temp.as_admin();
select is((select count(*)::int from public.road_hazards), 1, 'warnings are never deleted');

-- warehouse lots --------------------------------------------------------------------------------
select pg_temp.as_user(:a);
select lives_ok(format($f$insert into public.warehouse_lots (id, data) values ('L1', %L)$f$,
  jsonb_build_object('farmerId', :a, 'status', 'expected', 'remaining', 0, 'tag', null, 'qty', 40, 'zone', 'chilled', 'product', 'Beef', 'useBy', 1)),
  'a verified farm announces a deposit');
select throws_ok(format($f$insert into public.warehouse_lots (id, data) values ('L2', %L)$f$,
  jsonb_build_object('farmerId', :a, 'status', 'inStorage', 'remaining', 40, 'tag', 'T1', 'qty', 40, 'zone', 'chilled', 'product', 'Beef')),
  '42501', null, 'a farm cannot put stock straight into storage');
select throws_ok(format($f$insert into public.warehouse_lots (id, data) values ('L3', %L)$f$,
  jsonb_build_object('farmerId', :a, 'status', 'expected', 'remaining', 0, 'tag', null, 'qty', 40, 'zone', 'sauna', 'product', 'Beef')),
  '42501', null, 'the room type is checked');
select throws_ok(format($f$insert into public.warehouse_lots (id, data) values ('L4', %L)$f$,
  jsonb_build_object('farmerId', :b, 'status', 'expected', 'remaining', 0, 'tag', null, 'qty', 40, 'zone', 'chilled', 'product', 'Beef')),
  '42501', null, 'cannot announce for another farm');
select pg_temp.as_user(:b);
select is((select count(*)::int from public.warehouse_lots), 0, 'another farm sees nothing');
select pg_temp.as_user(:a);
select lives_ok($f$update public.warehouse_lots set data = data || '{"status":"inStorage","remaining":40}' where id = 'L1'$f$, 'a farm update is ignored');
select pg_temp.as_admin();
select is((select data ->> 'status' from public.warehouse_lots where id = 'L1'), 'expected', 'the farm cannot check its own stock in');
select pg_temp.as_user(:hub);
select is((select count(*)::int from public.warehouse_lots), 1, 'staff see all lots');
select lives_ok($f$update public.warehouse_lots set data = data || '{"status":"inStorage","remaining":40,"tag":"T1"}' where id = 'L1'$f$, 'staff check it in and tag it');
select throws_ok($f$update public.warehouse_lots set data = data || '{"zone":"frozen"}' where id = 'L1'$f$, '42501', null, 'staff cannot move it to another room type on paper');
select throws_ok($f$update public.warehouse_lots set data = data || '{"product":"Gold"}' where id = 'L1'$f$, '42501', null, 'or change the product');

-- picks, readings, certificates ------------------------------------------------------------------------------
select lives_ok($f$select public.save_pick('O1', '0', '{"product":"Beef","kg":2,"tags":["T1"]}')$f$, 'staff record a cut');
select lives_ok($f$select public.save_pick('O1', '1', '{"product":"Mince","kg":1,"tags":["T2"]}')$f$, 'and another line');
select is((select jsonb_object_keys_count from (select count(*)::int as jsonb_object_keys_count from jsonb_object_keys((select data -> 'lines' from public.warehouse_picks where id = 'O1'))) q), 2, 'both lines are kept');
select lives_ok($f$insert into public.warehouse_readings (id, at, data) values ('r1', 1, '{"at":1,"hub":"Durban","zone":"chilled","celsius":2.5}')$f$, 'staff log a temperature');
select pg_temp.as_user(:a);
select throws_ok($f$select public.save_pick('O1', '2', '{}')$f$, '42501', null, 'a farm cannot record cuts');
select is((select count(*)::int from public.warehouse_readings), 0, 'farms cannot read temperatures');
select throws_ok($f$insert into public.warehouse_readings (id, at, data) values ('r2', 1, '{}')$f$, '42501', null, 'or write them');

select pg_temp.as_user(:cert);
select lives_ok(format($f$insert into public.warehouse_certs (id, data) values ('C1', %L)$f$,
  jsonb_build_object('certifierId', :cert, 'rooms', jsonb_build_array('chilled'), 'issuedAt', 100, 'expiresAt', 200)), 'a certifier certifies the warehouse');
select throws_ok(format($f$insert into public.warehouse_certs (id, data) values ('C2', %L)$f$,
  jsonb_build_object('certifierId', :cert, 'rooms', jsonb_build_array('chilled'), 'issuedAt', 200, 'expiresAt', 100)), '42501', null, 'a certificate cannot expire before it starts');
select throws_ok(format($f$insert into public.warehouse_certs (id, data) values ('C3', %L)$f$,
  jsonb_build_object('certifierId', :cert, 'rooms', '[]'::jsonb, 'issuedAt', 100, 'expiresAt', 200)), '42501', null, 'it must name rooms');
select lives_ok($f$update public.warehouse_certs set data = data || '{"expiresAt": 999}' where id = 'C1'$f$, 'edits are ignored');
select pg_temp.as_admin();
select is((select (data ->> 'expiresAt')::int from public.warehouse_certs where id = 'C1'), 200, 'certificates are never edited');
select pg_temp.as_user(:a);
select throws_ok(format($f$insert into public.warehouse_certs (id, data) values ('C4', %L)$f$,
  jsonb_build_object('certifierId', :a, 'rooms', jsonb_build_array('chilled'), 'issuedAt', 100, 'expiresAt', 200)), '42501', null, 'a farm cannot certify');
select pg_temp.as_user(:hub);
select is((select count(*)::int from public.warehouse_certs), 1, 'staff can read certificates');

select * from finish();
rollback;
