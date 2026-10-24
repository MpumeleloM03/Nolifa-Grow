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
create function pg_temp.zone(p_id text, p_latest numeric, p_thr int) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'name', 'Test zone', 'provider', 'Utility', 'reservoir', 'Dam',
    'population', 1000, 'voteThreshold', p_thr, 'readings', '[]'::jsonb, 'latest', p_latest)
$$;

\set u '''aa000000-0000-0000-0000-000000000001'''
\set v1 '''aa000000-0000-0000-0000-000000000002'''
\set v2 '''aa000000-0000-0000-0000-000000000003'''
\set v3 '''aa000000-0000-0000-0000-000000000004'''
\set nv '''aa000000-0000-0000-0000-000000000005'''

insert into public.verified_users (uid) values (:v1), (:v2), (:v3);

-- only the provider writes zones ---------------------------------------------------
select pg_temp.as_user(:v1);
select throws_ok(format($f$insert into public.water_zones (id, data) values ('z1', %L)$f$, pg_temp.zone('z1', 30, 2)),
  '42501', null, 'a resident cannot publish a reservoir reading');
select pg_temp.as_user(:u, '{"utility": true}');
select lives_ok(format($f$insert into public.water_zones (id, data) values ('z1', %L)$f$, pg_temp.zone('z1', 30, 2)), 'the provider publishes a zone');
select lives_ok(format($f$insert into public.water_zones (id, data) values ('z2', %L)$f$, pg_temp.zone('z2', 80, 2)), 'a healthy zone');
select throws_ok(format($f$insert into public.water_zones (id, data) values ('z3', %L)$f$, pg_temp.zone('z3', 130, 2)),
  '42501', null, 'a level above 100 is refused');
select throws_ok(format($f$insert into public.water_zones (id, data) values ('z4', %L)$f$, pg_temp.zone('other', 50, 2)),
  '42501', null, 'the zone id must match');
select throws_ok(format($f$insert into public.water_zones (id, data) values ('z5', %L)$f$, pg_temp.zone('z5', 50, 2) || '{"extra": 1}'),
  '42501', null, 'unknown fields are refused');

-- voting ------------------------------------------------------------------------------
select pg_temp.as_user(:nv);
select throws_ok($f$select public.water_vote('z1')$f$, '42501', null, 'an unverified person cannot vote');
select pg_temp.as_user(:v1);
select is(public.water_vote('z2'), 'notEligible', 'a healthy community cannot start a request');
select is(public.water_vote('nope'), 'notEligible', 'an unknown zone is not eligible');
select is(public.water_vote('z1'), 'counted', 'the first voter opens an incident');
select is((select data ->> 'stage' from public.water_incidents where id = 'z1-1'), 'open', 'it waits for the threshold');
select is(public.water_vote('z1'), 'alreadyVoted', 'one person is one vote');
select is(public.water_has_voted('z1-1'), true, 'the voter can see they voted');
select pg_temp.as_user(:v2);
select is(public.water_has_voted('z1-1'), false, 'another person has not');
select is(public.water_vote('z1'), 'counted', 'a second person votes');
select is((select data ->> 'stage' from public.water_incidents where id = 'z1-1'), 'requested', 'the threshold sends it to the provider');
select is((select (data ->> 'votes')::int from public.water_incidents where id = 'z1-1'), 2, 'the count matches the votes');
select pg_temp.as_user(:v3);
select is(public.water_vote('z1'), 'counted', 'more voices are still counted once requested');
select is((select count(*)::int from public.water_votes), 1, 'a resident sees only their own vote');
select lives_ok($f$update public.water_incidents set data = data || '{"votes": 99}' where id = 'z1-1'$f$, 'a resident edit of the counter is ignored');
select pg_temp.as_admin();
select is((select (data ->> 'votes')::int from public.water_incidents where id = 'z1-1'), 3, 'the counter only moves with votes');
select pg_temp.as_user(:v3);
select throws_ok($f$insert into public.water_votes (incident_id, uid, at) values ('z1-1', 'x', 1)$f$, '42501', null, 'votes cannot be written directly');

-- the provider walks it forward --------------------------------------------------------------
select pg_temp.as_user(:u, '{"utility": true}');
select throws_ok($f$update public.water_incidents set stage = 'resolved', data = data || '{"stage":"resolved","resolvedAt":1}' where id = 'z1-1'$f$,
  '42501', null, 'it cannot skip straight to resolved');
select lives_ok($f$update public.water_incidents set data = data || '{"stage":"acknowledged","acknowledgedAt":1}' where id = 'z1-1'$f$, 'acknowledge');
select throws_ok($f$update public.water_incidents set data = data || '{"stage":"dispatched","dispatchedAt":1,"trucks":99,"etaMinutes":30,"note":""}' where id = 'z1-1'$f$,
  '42501', null, 'too many trucks is refused');
select lives_ok($f$update public.water_incidents set data = data || '{"stage":"dispatched","dispatchedAt":1,"trucks":2,"etaMinutes":30,"note":"on the way"}' where id = 'z1-1'$f$, 'dispatch');
select pg_temp.as_user(:v1);
select is(public.water_vote('z1'), 'notEligible', 'nobody can vote once trucks are dispatched');
select pg_temp.as_user(:u, '{"utility": true}');
select lives_ok($f$update public.water_incidents set data = data || '{"stage":"resolved","resolvedAt":2}' where id = 'z1-1'$f$, 'resolve');

-- next epoch needs the previous resolved ------------------------------------------------------------
select pg_temp.as_user(:v1);
select is(public.water_vote('z1'), 'counted', 'a new epoch opens after the old one is resolved');
select is((select epoch from public.water_incidents where id = 'z1-2'), 2, 'epoch 2');
select is((select count(*)::int from public.water_incidents where zone_id = 'z1' and stage <> 'resolved'), 1, 'only one live incident per zone');

-- dry taps: the dam is full, the street is not ---------------------------------------------------------
select pg_temp.as_user(:u, '{"utility": true}');
select lives_ok(format($f$insert into public.water_zones (id, data) values ('z6', %L)$f$,
  pg_temp.zone('z6', 90, 2) || '{"source": "DWS weekly State of Dams"}'), 'a zone may name its data source');
select throws_ok(format($f$insert into public.water_zones (id, data) values ('z7', %L)$f$,
  pg_temp.zone('z7', 90, 2) || jsonb_build_object('source', repeat('x', 300))), '42501', null, 'a very long source is refused');
select pg_temp.as_user(:v1);
select is(public.water_vote('z6'), 'notEligible', 'a healthy dam does not open a low-supply request');
select is(public.water_vote('z6', 'nonsense'), 'notEligible', 'an unknown reason is refused');
select is(public.water_vote('z6', 'dry_taps'), 'counted', 'dry taps can be reported while the dam is full');
select is((select data ->> 'reason' from public.water_incidents where id = 'z6-1'), 'dry_taps', 'the incident keeps its reason');
select is(public.water_vote('z6', 'dry_taps'), 'alreadyVoted', 'one person is still one report');
select pg_temp.as_user(:v2);
select is(public.water_vote('z6'), 'counted', 'a neighbour can join with a plain request');
select is((select data ->> 'stage' from public.water_incidents where id = 'z6-1'), 'requested', 'enough different people send it on');

-- prefs are private --------------------------------------------------------------------------------------
select pg_temp.as_user(:v1);
select lives_ok(format($f$insert into public.water_prefs (uid, data) values (%L, %L)$f$, :v1,
  '{"zoneId":"z1","household":4,"tankLitres":5000,"herd":10}'::jsonb), 'own prefs save');
select throws_ok(format($f$insert into public.water_prefs (uid, data) values (%L, %L)$f$, :v1,
  '{"zoneId":"z1","household":4,"tankLitres":5000,"herd":-1}'::jsonb), '42501', null, 'bad numbers are refused (own row)');
select throws_ok(format($f$insert into public.water_prefs (uid, data) values (%L, %L)$f$, :v2,
  '{"zoneId":"z1","household":4,"tankLitres":5000,"herd":-1}'::jsonb), '42501', null, 'bad numbers are refused');
select throws_ok(format($f$insert into public.water_prefs (uid, data) values (%L, %L)$f$, :v1,
  '{"household":4}'::jsonb), '42501', null, 'missing fields are refused');
select pg_temp.as_user(:v2);
select is((select count(*)::int from public.water_prefs), 0, 'another person sees none');

select * from finish();
rollback;
