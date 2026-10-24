begin;
select * from no_plan();

create function pg_temp.as_user(p_uid text, p_meta jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'app_metadata', p_meta)::text, true);
  execute 'set local role authenticated';
end $$;

\set adm '''a1000000-0000-0000-0000-000000000001'''
\set farmer '''a1000000-0000-0000-0000-000000000002'''
insert into auth.users (id, email) values (:adm::uuid, 'boss@example.com'), (:farmer::uuid, 'f@example.com');
insert into public.admins (uid) values (:adm);

select pg_temp.as_user(:farmer);
select throws_ok($f$select public.log_photo_view('verification', 'x/id.jpg')$f$, '42501', null, 'a farmer cannot write the log');
select is((select count(*)::int from public.id_photo_views), 0, 'or read it');
select pg_temp.as_user(:adm);
select lives_ok($f$select public.log_photo_view('verification', 'u1/id.jpg')$f$, 'an admin logs a view');
select is((select staff_email from public.id_photo_views limit 1), 'boss@example.com', 'with their own address');
select lives_ok($f$update public.id_photo_views set path = 'hidden'$f$, 'an update is silently ignored');
select lives_ok($f$delete from public.id_photo_views$f$, 'and so is a delete');
select is((select path from public.id_photo_views), 'u1/id.jpg', 'the row is unchanged');
select throws_ok($f$insert into public.id_photo_views (staff_uid, bucket, path) values ('x', 'b', 'p')$f$, '42501', null, 'or written around the function');

select * from finish();
rollback;
