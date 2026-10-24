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
create function pg_temp.job(p_route text, p_fee numeric, p_km numeric) returns jsonb language sql as $$
  select jsonb_build_object('route', p_route, 'deliveryFee', p_fee, 'distanceKm', p_km)
$$;
-- An order the driver has already collected, put there by the server side for the test.
create function pg_temp.seed(p_id text, p_cust text, p_farm text, p_driver text, p_extra jsonb) returns void language plpgsql as $$
begin
  insert into public.market_orders (id, data) values (p_id, jsonb_build_object(
    'id', p_id, 'customerId', p_cust, 'farmerId', p_farm, 'driverId', p_driver, 'driver', 'Driver', 'status', 'pickedUp',
    'lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Eggs', 'qty', 1, 'price', 80, 'ownerId', p_farm)),
    'deliveryFee', 25, 'serviceFee', 2.4, 'method', 'fnbPay', 'route', 'local', 'distanceKm', 8, 'customer', 'Buyer',
    'dropArea', 'Street', 'released', false, 'dispute', null, 'pinHash', 'server', 'pickupProof', true,
    'participants', jsonb_build_array(p_cust, p_farm, p_driver), 'rev', 3) || p_extra);
  insert into public.order_pins (order_id, pin_hash) values (p_id, extensions.crypt('4321', extensions.gen_salt('bf', 4)));
end $$;

\set buyer '''b0000000-0000-0000-0000-000000000001'''
\set farmer '''f0000000-0000-0000-0000-000000000002'''
\set d1 '''d0000000-0000-0000-0000-000000000003'''
\set d2 '''d0000000-0000-0000-0000-000000000004'''
\set med '''c0000000-0000-0000-0000-000000000007'''

insert into public.approved_drivers (uid) values (:d1), (:d2);

-- the formula, pinned to the same numbers as the Dart package ------------------------
select is(public.driver_job_pay(pg_temp.job('local', 15, 1)), 24.00, 'a very short trip pays the R24 minimum');
select is(public.driver_job_pay(pg_temp.job('local', 15, 5)), 24.50, 'R12 + 5 km at R2.50');
select is(public.driver_job_pay(pg_temp.job('local', 25, 8)), 32.00, 'R12 + 8 km at R2.50');
select is(public.driver_job_pay(pg_temp.job('local', 45, 20)), 62.00, 'R12 + 20 km at R2.50');
select is(public.driver_job_pay(pg_temp.job('local', 15, 70)), 45.75, 'an inflated distance is capped by what the fee could buy (13.5 km)');
select is(public.driver_job_pay(pg_temp.job('local', 15, 0)), 37.00, 'an unknown distance is treated as 10 km');
select is(public.driver_job_pay(pg_temp.job('hub', 35, 70)), 49.50, 'a hub order is paid for 15 km of last mile');
select is(public.driver_job_pay(pg_temp.job('hub', 50, 70)), 124.50, 'a longer last mile pays more');

-- the server records it when the PIN is accepted ------------------------------------
select pg_temp.seed('D1', :buyer, :farmer, :d1, '{}');
select pg_temp.seed('D2', :buyer, :farmer, :d1, '{"selfDelivery": true, "driverId": null}');
select pg_temp.as_user(:d1);
select is((select count(*)::int from public.driver_payouts), 0, 'nothing is owed before delivery');
select is(public.deliver_with_pin('D1', '4321') ->> 'outcome', 'delivered', 'the right PIN delivers');
select is((select amount from public.driver_payouts where order_id = 'D1'), 32.00, 'the driver is owed the formula amount');
select is((select state from public.driver_payouts where order_id = 'D1'), 'pending', 'it waits for the customer');
select is((select topup from public.driver_payouts where order_id = 'D1'), 12.00, 'Nolifa tops up what the fee does not cover (R32 less 80% of R25)');
select is((select base + distance_pay from public.driver_payouts where order_id = 'D1'), 32.00, 'the parts add up');
select throws_ok($f$insert into public.driver_payouts (order_id, driver_id, amount, base, distance_pay, km, delivery_fee) values ('X', 'd', 1, 1, 1, 1, 1)$f$,
  '42501', null, 'a driver cannot write a payout');
select lives_ok($f$update public.driver_payouts set amount = 999 where order_id = 'D1'$f$, 'an update is silently ignored');
select is((select amount from public.driver_payouts where order_id = 'D1'), 32.00, 'so a driver cannot raise one');
select pg_temp.as_user(:d2);
select is((select count(*)::int from public.driver_payouts), 0, 'another driver cannot see it');

-- released with the order -----------------------------------------------------------------
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"released": true, "rev": 5}' where id = 'D1'$f$, 'the customer confirms');
select pg_temp.as_user(:d1);
select is((select state from public.driver_payouts where order_id = 'D1'), 'released', 'the payout is released with it');

-- a refunded order pays nothing -------------------------------------------------------------
select pg_temp.as_admin();
select pg_temp.seed('D3', :buyer, :farmer, :d1, '{}');
select pg_temp.as_user(:d1);
select public.deliver_with_pin('D3', '4321');
select pg_temp.as_user(:buyer);
select lives_ok($f$update public.market_orders set data = data || '{"dispute": {"reason": "notDelivered", "stage": "open", "outcome": null, "note": "x", "timeline": []}, "rev": 5}' where id = 'D3'$f$, 'the customer disputes');
select pg_temp.as_user(:med, '{"mediator": true}');
select lives_ok($f$update public.market_orders set data = data || '{"dispute": {"reason": "notDelivered", "stage": "resolved", "outcome": "fullRefund", "note": "x", "timeline": []}, "released": true, "rev": 6}' where id = 'D3'$f$, 'the mediator refunds in full');
select pg_temp.as_admin();
select is((select state || ':' || amount::text from public.driver_payouts where order_id = 'D3'), 'cancelled:0.00', 'the driver is not paid for a full refund');

-- self delivery has no payout ----------------------------------------------------------------
select is((select count(*)::int from public.driver_payouts where order_id = 'D2'), 0, 'a farm that delivers itself has no driver payout');

select * from finish();
rollback;
