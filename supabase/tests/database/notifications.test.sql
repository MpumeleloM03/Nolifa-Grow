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

\set f '''a4000000-0000-0000-0000-000000000001'''
\set adm '''a4000000-0000-0000-0000-000000000002'''

insert into public.admins (uid) values (:adm);
insert into public.users (uid, data) values (:f, '{"name":"Sipho","region":"Greater Durban"}');
insert into public.memberships (uid, tier, status, monthly_price, accepted_terms_at, started_at, term_ends_at)
  values (:f, 'max', 'active', 7000, now(), now(), now() + interval '24 months');

select pg_temp.as_user(:adm);
select lives_ok($f$select public.set_notify_config('staff@example.com', 'vet@example.com')$f$, 'an admin sets who gets the alerts');
select is((public.get_notify_config() ->> 'vet_email'), 'vet@example.com', 'and can read them back');
select pg_temp.as_user(:f);
select throws_ok($f$select public.set_notify_config('x@example.com', 'x@example.com')$f$, '42501', null, 'a farmer cannot change them');
select is(public.get_notify_config(), null, 'or read them');

-- a vet video queues an alert with a link to the file ----------------------------------------
select public.open_consult('Limping cow', 'Front left leg since Monday', 'a1', 'Bessie', 'Cow');
select pg_temp.as_admin();
create temp table cid as select id from public.consults where farmer_id = :f limit 1;
grant select on cid to authenticated;
select pg_temp.as_user(:f);
select lives_ok(format($f$insert into public.consult_videos (consult_id, farmer_id, path, duration_s) values (%L, %L, 'a4/x/v.mp4', 75)$f$, (select id from cid), :f), 'the farmer sends a video');
select pg_temp.as_admin();
select is((select count(*)::int from public.outbox where kind = 'vet_video'), 1, 'the vet gets one alert');
select is((select to_email from public.outbox where kind = 'vet_video'), 'vet@example.com', 'sent to the vet address');
select is((select link_path from public.outbox where kind = 'vet_video'), 'a4/x/v.mp4', 'with the video to link to');
select ok((select body like '%Sipho%' and body like '%Bessie%' and body like '%Front left leg%' from public.outbox where kind = 'vet_video'), 'saying who, which animal and what was seen');
select is((select status from public.outbox where kind = 'vet_video'), 'pending', 'waiting to be sent');

-- a visit request, borehole and membership ---------------------------------------------------------
select pg_temp.as_user(:f);
select public.request_vet_visit((select id from cid), current_date + 3, 'Gate code 1234');
select public.request_borehole('farm', -29.8, 30.9, 'Past the dam', '0821234567', 'Dry spot', true);
select pg_temp.as_admin();
select is((select count(*)::int from public.outbox where kind = 'vet_visit'), 1, 'a visit request alerts the vet');
select is((select to_email from public.outbox where kind = 'borehole'), 'staff@example.com', 'a borehole request alerts staff');
select ok((select body ilike '%max%' and body like '%Past the dam%' from public.outbox where kind = 'borehole'), 'with the tier, discount and place');

-- the outbox is private to admins -----------------------------------------------------------------------
select pg_temp.as_user(:f);
select is((select count(*)::int from public.outbox), 0, 'a farmer cannot read the outbox');
select pg_temp.as_user(:adm);
select ok((select count(*)::int from public.outbox) >= 3, 'an admin can');
select lives_ok($f$select public.kick_outbox_now()$f$, 'sending can be started from the back office (a no-op until a mail function is set)');
select pg_temp.as_user(:f);
select throws_ok($f$select public.kick_outbox_now()$f$, '42501', null, 'but not by a farmer');

select * from finish();
rollback;
