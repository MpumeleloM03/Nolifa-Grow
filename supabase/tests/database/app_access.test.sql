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

\set farmer '''f1000000-0000-0000-0000-000000000001'''
\set buyer '''b1000000-0000-0000-0000-000000000002'''
\set driver '''d1000000-0000-0000-0000-000000000003'''
\set driver2 '''d1000000-0000-0000-0000-000000000004'''
\set other '''e1000000-0000-0000-0000-000000000005'''
\set staff '''c1000000-0000-0000-0000-000000000006'''

insert into public.verified_users (uid) values (:farmer);
insert into public.approved_drivers (uid) values (:driver), (:driver2);
insert into public.staff (uid, name) values (:staff, 'Hub');
insert into public.users (uid, data) values (:farmer, '{"name":"Fatboy Test"}');

-- approvals reach the person ----------------------------------------------------------
insert into public.farm_applications (uid, status, data) values (:farmer, 'submitted', '{}');
insert into public.driver_applications (uid, status, data) values (:driver, 'submitted', '{}');
update public.farm_applications set status = 'approved' where uid = :farmer;
update public.driver_applications set status = 'needs_info', review_note = 'Licence photo is blurry' where uid = :driver;
select pg_temp.as_user(:farmer);
select is((select title from public.notifications where kind = 'farm_application'), 'Your farm is approved', 'a farm hears it was approved');
select pg_temp.as_user(:driver);
select is((select body from public.notifications where kind = 'driver_application'), 'Licence photo is blurry', 'a driver is told what is missing');
select is((select count(*)::int from public.notifications), 1, 'and sees only their own notices');
select pg_temp.as_user(:other);
select is((select count(*)::int from public.notifications), 0, 'a stranger sees none');
select lives_ok($f$select public.mark_notifications_read()$f$, 'notices can be marked read');
select throws_ok($f$select public.notify_user('x', 'k', 't')$f$, '42501', null, 'nobody can write a notice by hand');

-- orders: the seller hears, the buyer follows ---------------------------------------------
select pg_temp.as_admin();
insert into public.market_orders (id, data) values ('ORD-AAAAA', jsonb_build_object('id', 'ORD-AAAAA', 'customerId', :buyer, 'farmerId', :farmer, 'status', 'newOrder',
  'customer', 'Lindiwe', 'pickup', 'Fatboy Butcheries', 'dropArea', 'Umhlanga', 'participants', jsonb_build_array(:buyer, :farmer), 'released', false, 'dispute', null, 'driverId', null, 'rev', 0));
select is((select count(*)::int from public.notifications where uid = :farmer and kind = 'order_new'), 1, 'the seller is told of a new order');
update public.market_orders set data = data || jsonb_build_object('status', 'findingDriver', 'rev', 1) where id = 'ORD-AAAAA';
update public.market_orders set data = data || jsonb_build_object('status', 'assigned', 'driverId', :driver, 'driver', 'Sipho', 'rev', 2) where id = 'ORD-AAAAA';
select is((select count(*)::int from public.notifications where uid = :buyer and kind = 'order_driver'), 1, 'the buyer hears a driver is coming');

-- driver locations --------------------------------------------------------------------------------
select pg_temp.as_user(:driver);
select lives_ok($f$select public.post_location(-29.78, 31.05, 90, 40, 8)$f$, 'an approved driver shares a position');
select pg_temp.as_user(:other);
select throws_ok($f$select public.post_location(-29.78, 31.05)$f$, '42501', null, 'someone who is not a driver cannot');
select is((select count(*)::int from public.driver_locations), 0, 'and cannot see drivers');
select pg_temp.as_user(:buyer);
select is((select count(*)::int from public.driver_locations), 1, 'the buyer sees the driver bringing their order');
select is(drop_api.track_order('ORD-AAAAA') -> 'driver' ->> 'name', 'Sipho', 'tracking names the driver');
select is((drop_api.track_order('ORD-AAAAA') -> 'driver' ->> 'lat')::numeric, -29.78, 'and shows where they are');
select pg_temp.as_user(:driver2);
select is((select count(*)::int from public.driver_locations), 0, 'another driver cannot see them');
select throws_ok($f$select drop_api.track_order('ORD-AAAAA')$f$, '42501', null, 'or track the order');
select pg_temp.as_user(:farmer);
select is((select count(*)::int from public.driver_locations), 1, 'the seller sees the driver collecting their order');
select pg_temp.as_user(:staff);
select is((select count(*)::int from public.driver_locations), 1, 'staff see every driver');
select pg_temp.as_admin();
update public.market_orders set data = data || '{"status":"delivered","rev":3}' where id = 'ORD-AAAAA';
select pg_temp.as_user(:buyer);
select is((select count(*)::int from public.driver_locations), 0, 'once delivered the driver is no longer visible to the buyer');

-- room climate and the farmer's own stock ------------------------------------------------------------------
select pg_temp.as_admin();
insert into public.warehouse_lots (id, data) values ('L1', jsonb_build_object('id', 'L1', 'hub', 'Durban hub', 'farmerId', :farmer, 'product', 'Beef mince',
  'zone', 'chilled', 'status', 'stored', 'qty', 20, 'remaining', 14, 'useBy', 1793000000000, 'tag', 'NLF-1', 'bay', 'C1'));
insert into public.market_products (id, owner_id, data) values ('P1', :farmer, '{"name":"Beef mince","farm":"Fatboy Test","stock":8,"price":89,"unit":"kg","emoji":"🥩"}');
insert into public.warehouse_readings (id, at, data) values ('R1', 1000, '{"hub":"Durban hub","zone":"chilled","c":2.5,"at":1000}');
select pg_temp.as_user(:farmer);
select is((select ok from public.room_climate where zone = 'chilled'), true, 'the farmer sees their room is cold enough');
select is(grow_api.my_inventory() -> 0 -> 'warehouse' ->> 'remaining', '14', 'inventory shows what the warehouse holds');
select is(grow_api.my_inventory() -> 0 ->> 'shopStock', '8', 'and what the shop has');
select is(grow_api.my_inventory() -> 0 -> 'warehouse' ->> 'nextUseBy', '1793000000000', 'and when it must be used by');
select is((grow_api.my_inventory() -> 0 -> 'warehouse' ->> 'tempC')::numeric, 2.5, 'and the room temperature');
select pg_temp.as_user(:other);
select is((select count(*)::int from public.room_climate), 0, 'a farm with nothing in the room does not see it');
select is(jsonb_array_length(grow_api.my_inventory()), 0, 'and has no inventory');
select pg_temp.as_admin();
insert into public.warehouse_readings (id, at, data) values ('R2', 2000, '{"hub":"Durban hub","zone":"chilled","c":8.4,"at":2000}');
select is((select ok from public.room_climate where zone = 'chilled'), false, 'a warm reading flips the room');
select is((select count(*)::int from public.notifications where uid = :farmer and kind = 'cold_alarm'), 1, 'the farmer gets a temperature alert');
insert into public.warehouse_readings (id, at, data) values ('R3', 3000, '{"hub":"Durban hub","zone":"chilled","c":9.0,"at":3000}');
select is((select count(*)::int from public.notifications where uid = :farmer and kind = 'cold_alarm'), 1, 'and only one while it stays warm');

-- truck hire ----------------------------------------------------------------------------------------------------
select pg_temp.as_user(:other);
select throws_ok($f$select public.request_truck('bakkie', 500, false, 'Fatboy', 'Durban hub', 20, current_date + 2)$f$, '42501', null, 'only a verified farm can hire');
select pg_temp.as_user(:farmer);
select throws_ok($f$select public.request_truck('flatbed', 500, true, 'Fatboy', 'Durban hub', 20, current_date + 2)$f$, 'P0001', null, 'a flatbed cannot hold cold goods');
select throws_ok($f$select public.request_truck('bakkie', 500, false, 'Fatboy', 'Durban hub', 20, current_date - 1)$f$, 'P0001', null, 'the day cannot be in the past');
select lives_ok($f$select public.request_truck('refrigerated', 2000, true, 'Umhlanga', 'Durban hub', 25, current_date + 3, 'Beef for the hub')$f$, 'a verified farm asks for a truck');
select is((select estimate from public.truck_hire), 1450.00, 'the server prices it: R900 + 25 km at R22');
select is((select status from public.truck_hire), 'requested', 'it waits for staff');
select throws_ok($f$select public.quote_truck((select id from public.truck_hire), 1200)$f$, '42501', null, 'the farm cannot quote itself');
select pg_temp.as_user(:staff);
select lives_ok($f$select public.quote_truck((select id from public.truck_hire), 1300)$f$, 'staff quote it');
select pg_temp.as_user(:farmer);
select is((select count(*)::int from public.notifications where kind = 'truck'), 1, 'the farm hears the quote is ready');
select lives_ok($f$select public.accept_truck((select id from public.truck_hire))$f$, 'the farm accepts');
select is((select status from public.truck_hire), 'booked', 'and it is booked');
select pg_temp.as_user(:other);
select is((select count(*)::int from public.truck_hire), 0, 'another farm cannot see it');

-- the doors are closed to signed-out callers -------------------------------------------------------------------------
select pg_temp.as_admin();
set local role anon;
select throws_ok($f$select drop_api.farms()$f$, '42501', null, 'anonymous callers cannot use the Drop door');
select throws_ok($f$select grow_api.my_inventory()$f$, '42501', null, 'or the Grow door');
select throws_ok($f$select delivery_api.my_payouts()$f$, '42501', null, 'or the Delivery door');
reset role;
select pg_temp.as_user(:buyer);
select is(jsonb_array_length(drop_api.farms()), 1, 'a household sees the farm and its stock');
select is(drop_api.farms() -> 0 ->> 'inStock', '1', 'with the count that is in stock');

select * from finish();
rollback;
