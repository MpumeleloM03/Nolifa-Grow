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

\set f1 '''f1000000-0000-0000-0000-000000000001'''
\set f2 '''f1000000-0000-0000-0000-000000000002'''
\set f3 '''f1000000-0000-0000-0000-000000000003'''
\set vet '''f1000000-0000-0000-0000-000000000004'''
\set adm '''f1000000-0000-0000-0000-000000000005'''

insert into public.vets (uid, name) values (:vet, 'Dr Naidoo');
insert into public.admins (uid) values (:adm);
insert into public.users (uid, data) values
  (:f1, '{"region":"Greater Durban"}'), (:f2, '{"region":"Greater Durban"}'), (:f3, '{"region":"Other"}');

-- joining ----------------------------------------------------------------------
select pg_temp.as_user(:f1);
select is(public.membership_tier(:f1), 'none', 'no membership at first');
select throws_ok($f$select public.open_consult('Limping cow', 'x', null, '', '')$f$, '42501', null, 'a consult needs a membership');
select lives_ok($f$select public.join_membership('member')$f$, 'a farmer signs up for the 3k plan');
select is(public.membership_tier(:f1), 'none', 'still nothing until payment is confirmed');
select throws_ok($f$select public.activate_membership('f1000000-0000-0000-0000-000000000001', 'EFT1')$f$, '42501', null, 'a farmer cannot activate themselves');
select throws_ok($f$insert into public.memberships (uid, tier, monthly_price, accepted_terms_at) values ('f1000000-0000-0000-0000-000000000001', 'max', 1, now())$f$, '42501', null, 'no direct inserts');
select throws_ok($f$select public.join_membership('gold')$f$, 'P0001', null, 'unknown plan');

select pg_temp.as_user(:adm);
select lives_ok($f$select public.activate_membership('f1000000-0000-0000-0000-000000000001', 'EFT-1')$f$, 'an admin activates after payment');
select is(public.membership_tier(:f1), 'member', 'member tier now counts');
select is((select term_months from public.memberships where uid = :f1), 24, 'the term is 24 months');
select ok((select term_ends_at > now() + interval '23 months' from public.memberships where uid = :f1), 'the term ends in two years');
select is((select monthly_price from public.memberships where uid = :f1), 3000, 'R3 000 a month');

select pg_temp.as_user(:f1);
select throws_ok($f$select public.join_membership('max')$f$, 'P0001', null, 'an active member cannot just sign up again');

-- video quota ------------------------------------------------------------------------
select lives_ok($f$select public.open_consult('Limping cow', 'Front left leg', 'a1', 'Bessie', 'cattle')$f$, 'a member opens a case');
select is(public.videos_left(), 4, 'four videos for a member');
select pg_temp.as_admin();
create temp table cid as select id from public.consults where farmer_id = :f1 limit 1;
grant select on cid to authenticated;
select pg_temp.as_user(:f1);
select throws_ok(format($f$insert into public.consult_videos (consult_id, farmer_id, path, duration_s) values (%L, %L, 'p', 121)$f$, (select id from cid), :f1),
  '23514', null, 'a video cannot be longer than two minutes');
select lives_ok(format($f$insert into public.consult_videos (consult_id, farmer_id, path, duration_s) values (%L, %L, 'a/1', 100), (%L, %L, 'a/2', 100), (%L, %L, 'a/3', 100), (%L, %L, 'a/4', 120)$f$,
  (select id from cid), :f1, (select id from cid), :f1, (select id from cid), :f1, (select id from cid), :f1), 'four videos are accepted');
select is(public.videos_left(), 0, 'none left');
select throws_ok(format($f$insert into public.consult_videos (consult_id, farmer_id, path, duration_s) values (%L, %L, 'a/5', 60)$f$, (select id from cid), :f1),
  'P0002', null, 'the fifth is refused');
select throws_ok(format($f$insert into public.consult_videos (consult_id, farmer_id, path, duration_s) values (%L, %L, 'a/6', 60)$f$, (select id from cid), :f2),
  '42501', null, 'cannot upload for someone else');

-- strangers and vets ---------------------------------------------------------------------
select pg_temp.as_user(:f2);
select is((select count(*)::int from public.consults), 0, 'another farmer sees no cases');
select is((select count(*)::int from public.consult_videos), 0, 'or videos');
select pg_temp.as_user(:vet);
select is((select count(*)::int from public.consults), 1, 'a vet sees cases from their province');
select is((select count(*)::int from public.consult_videos), 4, 'and the videos');
select throws_ok(format($f$select public.vet_answer(%L, '{"suspected":"Foot rot"}')$f$, (select id from cid)), 'P0001', null, 'a diagnosis needs all four parts');
select lives_ok(format($f$select public.vet_answer(%L, %L)$f$, (select id from cid),
  '{"suspected":"Foot rot","why":"Swelling and smell between the claws","remedy":"Clean, topical copper sulphate, 5 days","howItHelps":"Kills the bacteria and dries the lesion","urgency":"soon"}'::jsonb), 'a vet answers in full');
select is((select status from public.consults where id = (select id from cid)), 'answered', 'the case is answered');
select lives_ok(format($f$select public.send_consult_message(%L, 'Keep her in a dry camp')$f$, (select id from cid)), 'the vet messages');
select pg_temp.as_user(:f1);
select lives_ok(format($f$select public.send_consult_message(%L, 'Thank you doctor')$f$, (select id from cid)), 'the farmer replies');
select is((select count(*)::int from public.consult_messages), 2, 'both messages are in the chat');
select pg_temp.as_user(:f2);
select throws_ok(format($f$select public.send_consult_message(%L, 'hello')$f$, (select id from cid)), '42501', null, 'a stranger cannot chat in someone else''s case');
select pg_temp.as_user(:f1);
select throws_ok($f$select public.vet_answer('x', '{}')$f$, '42501', null, 'a farmer cannot write a diagnosis');

-- on-site visits: Max only, partner province only ------------------------------------------------
select throws_ok(format($f$select public.request_vet_visit(%L, current_date + 3, 'please')$f$, (select id from cid)), '42501', null, 'a 3k member cannot request a visit');
select pg_temp.as_user(:f2);
select public.join_membership('max');
select pg_temp.as_user(:adm);
select public.activate_membership(:f2, 'EFT-2');
select pg_temp.as_user(:f2);
select is(public.videos_left(), 15, 'fifteen videos for Max');
select public.open_consult('Calf off feed', '', null, '', 'cattle');
select pg_temp.as_admin();
create temp table cid2 as select id from public.consults where farmer_id = :f2 limit 1;
grant select on cid2 to authenticated;
select pg_temp.as_user(:f2);
select lives_ok(format($f$select public.request_vet_visit(%L, current_date + 3, 'Gate code 1234')$f$, (select id from cid2)), 'a Max member in KZN requests a visit');
select pg_temp.as_user(:vet);
select lives_ok(format($f$select public.book_vet_visit(%L, current_date + 4, 'Arriving at 9')$f$, (select id from cid2)), 'the vet books it');
select is((select status from public.consults where id = (select id from cid2)), 'visit_booked', 'booked');

select pg_temp.as_admin();
insert into public.memberships (uid, tier, status, monthly_price, accepted_terms_at, started_at, term_ends_at)
  values (:f3, 'max', 'active', 7000, now(), now(), now() + interval '24 months');
select pg_temp.as_user(:f3);
select public.open_consult('Sheep limping', '', null, '', 'sheep');
select pg_temp.as_admin();
create temp table cid3 as select id from public.consults where farmer_id = :f3 limit 1;
grant select on cid3 to authenticated;
select pg_temp.as_user(:f3);
select throws_ok(format($f$select public.request_vet_visit(%L, current_date + 3, '')$f$, (select id from cid3)), 'P0003', null, 'outside a partner province the visit is refused');
select is((select province from public.consults where id = (select id from cid3)), 'Unknown', 'province is recorded on the case');

-- verification ---------------------------------------------------------------------------------
select pg_temp.as_user(:f1);
select lives_ok($f$select public.save_application('{"fullName":"A Farmer","idNumber":"8001015009087","phone":"0821234567","farmName":"Green Hills","province":"KwaZulu-Natal","lat":-29.8,"lng":30.9,"sizeHa":12,"farmKind":"livestock","consent":true}'::jsonb)$f$, 'a draft saves');
select throws_ok($f$select public.submit_application()$f$, 'P0004', null, 'submit needs the photos');
select throws_ok($f$select public.add_application_file('id_front', 'someone-else/id.jpg')$f$, '42501', null, 'a file path must be in your own folder');
select lives_ok($f$select public.add_application_file('id_front', 'f1000000-0000-0000-0000-000000000001/id.jpg')$f$, 'ID photo');
select lives_ok($f$select public.add_application_file('selfie_with_id', 'f1000000-0000-0000-0000-000000000001/selfie.jpg')$f$, 'selfie');
select lives_ok($f$select public.add_application_file('land_photo', 'f1000000-0000-0000-0000-000000000001/land.jpg')$f$, 'land photo');
select throws_ok($f$select public.submit_application()$f$, 'P0004', null, 'submit also needs the farm logo and the store picture');
select lives_ok($f$select public.add_application_file('farm_logo', 'f1000000-0000-0000-0000-000000000001/logo.png')$f$, 'farm logo');
select lives_ok($f$select public.add_application_file('farm_banner', 'f1000000-0000-0000-0000-000000000001/banner.jpg')$f$, 'store picture');
select lives_ok($f$select public.submit_application()$f$, 'now it submits');
select is((select status from public.farm_applications where uid = :f1), 'submitted', 'waiting for review');
select throws_ok($f$select public.save_application('{}'::jsonb)$f$, 'P0001', null, 'it cannot be edited while under review');
select throws_ok($f$select public.review_application('f1000000-0000-0000-0000-000000000001', 'approved', '')$f$, '42501', null, 'a farmer cannot approve themselves');
select pg_temp.as_user(:adm);
select throws_ok($f$select public.review_application('f1000000-0000-0000-0000-000000000001', 'rejected', '')$f$, 'P0001', null, 'a rejection must say why');
select lives_ok($f$select public.review_application('f1000000-0000-0000-0000-000000000001', 'approved', 'Documents match')$f$, 'an admin approves');
select pg_temp.as_user(:f1);
select ok(exists (select 1 from public.verified_users where uid = :f1), 'the farmer is now verified');
select pg_temp.as_user(:adm);
select is((select data ->> 'farmName' from public.farm_profiles where uid = :f1), 'Green Hills', 'a public farm profile exists');
select is((select data ->> 'logo' from public.farm_profiles where uid = :f1), 'f1000000-0000-0000-0000-000000000001/logo.png', 'approval publishes the logo');
select is((select data ->> 'banner' from public.farm_profiles where uid = :f1), 'f1000000-0000-0000-0000-000000000001/banner.jpg', 'and the store picture');
select pg_temp.as_user(:f1);
select throws_ok($f$select public.set_farm_brand('someone-else/logo.png', null)$f$, '42501', null, 'a farm can only point at its own files');
select lives_ok($f$select public.set_farm_brand(null, 'f1000000-0000-0000-0000-000000000001/banner2.jpg')$f$, 'an approved farm changes its store picture');
select pg_temp.as_user(:adm);
select is((select data ->> 'banner' from public.farm_profiles where uid = :f1), 'f1000000-0000-0000-0000-000000000001/banner2.jpg', 'it goes live at once');
select is((select data ->> 'logo' from public.farm_profiles where uid = :f1), 'f1000000-0000-0000-0000-000000000001/logo.png', 'the logo is untouched');
select pg_temp.as_user(:f2);
select is((select count(*)::int from public.farm_applications), 0, 'other farmers cannot read the application');
select is((select count(*)::int from public.application_files), 0, 'or the ID photos');

-- boreholes --------------------------------------------------------------------------------------------
select pg_temp.as_user(:f1);
select throws_ok($f$select public.request_borehole('farm', -29.8, 30.9, 'Farm road', '0821234567', '', false)$f$, 'P0001', null, 'the reserve must be agreed to');
select lives_ok($f$select public.request_borehole('farm', -29.8, 30.9, 'Farm road', '0821234567', 'Dry spot near the dam', true)$f$, 'a member requests a borehole');
select is((select discount_pct from public.borehole_requests where uid = :f1), 10, 'the 3k member discount is recorded');
select is((select reserve_litres from public.borehole_requests where uid = :f1), 50000, '50 000 litres are reserved for Nolifa');
select pg_temp.as_user(:f3);
select public.request_borehole('community', -29.5, 30.1, '', '', '', true);
select is((select discount_pct from public.borehole_requests where uid = :f3), 15, 'Max gets the bigger discount');
select pg_temp.as_user(:adm);
select lives_ok($f$select public.quote_borehole('x', 1)$f$, 'quoting a missing request does nothing');
select lives_ok(format($f$select public.quote_borehole(%L, 100000)$f$, (select id from public.borehole_requests where uid = :f1)), 'staff quote the standard price');
select is((select final_quote from public.borehole_requests where uid = :f1), 90000, 'the member price is 10 percent off');
select pg_temp.as_user(:f1);
select lives_ok(format($f$select public.accept_borehole_quote(%L)$f$, (select id from public.borehole_requests where uid = :f1)), 'the farmer accepts the quote');
select pg_temp.as_user(:adm);
select lives_ok(format($f$select public.mark_borehole_drilled(%L)$f$, (select id from public.borehole_requests where uid = :f1)), 'drilled');
select is((select litres_reserved from public.water_reserves where owner_uid = :f1), 50000, 'a 50 000 litre reserve now exists');
select lives_ok(format($f$select public.log_collection(%L, 20000, 'School tanker')$f$, (select id from public.water_reserves where owner_uid = :f1)), 'Nolifa collects 20 000 litres');
select throws_ok(format($f$select public.log_collection(%L, 40000, 'too much')$f$, (select id from public.water_reserves where owner_uid = :f1)), 'P0001', null, 'it cannot collect more than is reserved');
select is((select litres_collected from public.water_reserves where owner_uid = :f1), 20000, 'the balance is tracked');
select pg_temp.as_user(:f2);
select throws_ok($f$select public.log_collection('x', 1, '')$f$, '42501', null, 'a farmer cannot log collections');

select * from finish();
rollback;
