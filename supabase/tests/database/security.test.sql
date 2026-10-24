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

\set a '''a3000000-0000-0000-0000-000000000001'''
\set b '''a3000000-0000-0000-0000-000000000002'''
\set drv '''a3000000-0000-0000-0000-000000000003'''
\set adm '''a3000000-0000-0000-0000-000000000004'''

insert into auth.users (id, instance_id, aud, role, email) values
  (:a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.com'),
  (:b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.com'),
  (:drv, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@example.com');
insert into public.admins (uid) values (:adm);
insert into public.users (uid, data) values (:a, '{"email":"a@example.com","name":"A"}'), (:b, '{"email":"b@example.com","name":"B"}');

-- emails are private ----------------------------------------------------------------
select pg_temp.as_user(:a);
select is((select count(*)::int from public.users), 1, 'a user only reads their own row');
select is((select data ->> 'email' from public.users limit 1), 'a@example.com', 'and it is their own email');
select lives_ok($f$update public.users set data = '{}' where uid = 'a3000000-0000-0000-0000-000000000002'$f$, 'editing someone else is silently ignored');
select pg_temp.as_admin();
select is((select data ->> 'name' from public.users where uid = :b), 'B', 'and nothing changed');
select pg_temp.as_user(:a);

-- outbreak spam ---------------------------------------------------------------------------
select throws_ok($f$insert into public.outbreaks (data) values ('{"lat":-29.5,"lng":30.2,"severity":"red"}')$f$, '42501', null, 'an unverified account cannot add outbreak reports');
select pg_temp.as_admin();
insert into public.verified_users (uid) values (:a);
select pg_temp.as_user(:a);
select lives_ok($f$insert into public.outbreaks (data) values ('{"lat":-29.5,"lng":30.2,"severity":"red"}')$f$, 'a verified one can');

-- driver application ------------------------------------------------------------------------
select pg_temp.as_user(:drv);
select is(public.is_approved_driver(), false, 'not approved at first');
select lives_ok($f$select public.save_driver_application('{"fullName":"D River","idNumber":"8001015009087","phone":"0821234567","vehicle":"bakkie","plate":"ND 123","licenceCode":"B","consent":true}'::jsonb)$f$, 'a draft saves');
select throws_ok($f$select public.submit_driver_application()$f$, 'P0004', null, 'it needs the photos');
select lives_ok($f$select public.add_application_file('driver_id_front', 'a3000000-0000-0000-0000-000000000003/id.jpg')$f$, 'ID photo');
select lives_ok($f$select public.add_application_file('driver_selfie_with_id', 'a3000000-0000-0000-0000-000000000003/s.jpg')$f$, 'selfie');
select lives_ok($f$select public.add_application_file('driver_licence', 'a3000000-0000-0000-0000-000000000003/l.jpg')$f$, 'licence');
select lives_ok($f$select public.add_application_file('driver_vehicle', 'a3000000-0000-0000-0000-000000000003/v.jpg')$f$, 'vehicle');
select lives_ok($f$select public.submit_driver_application()$f$, 'it submits');
select throws_ok($f$select public.review_driver_application('a3000000-0000-0000-0000-000000000003', 'approved', '')$f$, '42501', null, 'a driver cannot approve themselves');
select pg_temp.as_user(:adm);
select throws_ok($f$select public.review_driver_application('a3000000-0000-0000-0000-000000000003', 'rejected', '')$f$, 'P0001', null, 'a rejection says why');
select lives_ok($f$select public.review_driver_application('a3000000-0000-0000-0000-000000000003', 'approved', '')$f$, 'an admin approves');
select pg_temp.as_user(:drv);
select is(public.is_approved_driver(), true, 'now approved');

-- deleting an account --------------------------------------------------------------------------
select pg_temp.as_admin();
insert into public.market_products (id, owner_id, data) values ('DP', :b, jsonb_build_object('ownerId', :b, 'name', 'Eggs', 'price', 10));
insert into public.cattle (uid, id, data) values (:b, 'c1', '{}');
insert into public.market_orders (id, data) values ('DO1', jsonb_build_object('id', 'DO1', 'customerId', :b, 'farmerId', :a, 'status', 'delivered', 'released', true, 'dispute', null,
  'customer', 'B', 'dropArea', '1 Real Street', 'participants', jsonb_build_array(:b, :a), 'lines', '[]'::jsonb, 'deliveryFee', 25, 'serviceFee', 2, 'method', 'fnbPay', 'pinHash', 'server'));
insert into public.market_orders (id, data) values ('DO2', jsonb_build_object('id', 'DO2', 'customerId', :b, 'farmerId', :a, 'status', 'findingDriver', 'released', false, 'dispute', null,
  'customer', 'B', 'dropArea', '2 Real Street', 'participants', jsonb_build_array(:b, :a), 'lines', '[]'::jsonb, 'deliveryFee', 25, 'serviceFee', 2, 'method', 'fnbPay', 'pinHash', 'server'));
select pg_temp.as_user(:b);
select throws_ok($f$select public.delete_my_account()$f$, 'P0001', null, 'an account with an order in progress cannot be deleted yet');
select pg_temp.as_admin();
update public.market_orders set data = data || '{"status":"delivered","released":true}' where id = 'DO2';
select pg_temp.as_user(:b);
select lives_ok($f$select public.delete_my_account()$f$, 'once everything is finished, it can');
select pg_temp.as_admin();
select is((select count(*)::int from auth.users where id = :b), 0, 'the sign-in is gone');
select is((select count(*)::int from public.users where uid = :b), 0, 'the profile is gone');
select is((select count(*)::int from public.cattle where uid = :b), 0, 'the herd is gone');
select is((select count(*)::int from public.market_products where owner_id = :b), 0, 'the listings are gone');
select is((select data ->> 'dropArea' from public.market_orders where id = 'DO1'), 'Removed', 'order addresses are removed');
select is((select data ->> 'customer' from public.market_orders where id = 'DO1'), 'Deleted user', 'and the name');
select is((select count(*)::int from public.market_orders where id = 'DO1'), 1, 'but the order stays for the farm''s accounts');

select * from finish();
rollback;
