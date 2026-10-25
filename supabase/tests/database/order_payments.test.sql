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
create function pg_temp.order_json(p_id text, p_cust text, p_farm text, p_extra jsonb default '{}') returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'customerId', p_cust, 'farmerId', p_farm, 'status', 'newOrder',
    'lines', jsonb_build_array(jsonb_build_object('productId', 'P1', 'name', 'Eggs', 'qty', 3, 'price', 80, 'ownerId', p_farm)),
    'deliveryFee', 25, 'serviceFee', 7.2, 'method', 'fnbPay', 'route', 'local', 'customer', 'Buyer', 'dropArea', 'Street',
    'participants', jsonb_build_array(p_cust, p_farm), 'rev', 0) || p_extra
$$;

\set buyer '''b2000000-0000-0000-0000-000000000001'''
\set farmer '''f2000000-0000-0000-0000-000000000002'''
\set buyer2 '''b2000000-0000-0000-0000-000000000003'''

insert into public.seller_plans (uid, plan) values (:farmer, 'grow');
insert into public.market_products (id, owner_id, data) values ('P1', :farmer, jsonb_build_object('ownerId', :farmer, 'name', 'Eggs', 'price', 80, 'stock', 5));

-- a card order starts unpaid and takes stock at once --------------------------------------------
select pg_temp.as_user(:buyer);
select lives_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('PAY1', :buyer, :farmer)), 'the buyer places a card order');
select is((select data ->> 'paid' from public.market_orders where id = 'PAY1'), 'false', 'it starts unpaid');
select pg_temp.as_admin();
select is((select (data ->> 'stock')::int from public.market_products where id = 'P1'), 2, 'the shelf shrank on the server (5 - 3)');
select pg_temp.as_user(:buyer2);
select throws_ok(format($f$select public.place_order(%L, '4321')$f$, pg_temp.order_json('PAY2', :buyer2, :farmer)), 'P0005', null, 'a second buyer cannot take what is gone');

-- an unpaid order cannot be packed ------------------------------------------------------------------
select pg_temp.as_user(:farmer);
select throws_ok($f$update public.market_orders set data = data || '{"status":"findingDriver","commission":0.05,"rev":1}' where id = 'PAY1'$f$, 'P0001', null, 'the seller cannot pack an unpaid card order');
select pg_temp.as_user(:buyer);
select throws_ok($f$update public.market_orders set data = data || '{"paid": true, "rev": 1}' where id = 'PAY1'$f$, '42501', null, 'a buyer cannot mark their own order paid');
select pg_temp.as_admin();
select is((select data ->> 'paid' from public.market_orders where id = 'PAY1'), 'false', 'and it stays unpaid');

-- only the server can confirm ---------------------------------------------------------------------
insert into public.payments (id, uid, kind, tier, amount_cents, checkout_id, order_id) values ('pay-1', :buyer, 'order', 'order', 25400, 'chk-1', 'PAY1');
select is(public.order_amount_cents('PAY1'), 27220, 'the server works out the amount itself');
select pg_temp.as_user(:buyer);
select throws_ok($f$select public.activate_order_paid('pay-1', 'chk-1')$f$, '42501', null, 'a buyer cannot confirm their own payment');
select pg_temp.as_admin();
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(public.activate_order_paid('pay-1', 'chk-1'), 'paid', 'a confirmed payment marks the order paid');
select is(public.activate_order_paid('pay-1', 'chk-1'), 'already', 'and only once');
select is(public.activate_order_paid('pay-1', 'wrong'), 'unknown', 'a wrong checkout id is refused');
reset role;
select is((select data ->> 'paid' from public.market_orders where id = 'PAY1'), 'true', 'the order is paid');
select is((select count(*)::int from public.notifications where uid = :farmer and kind = 'order_paid'), 1, 'the seller is told to pack it');
select is((select count(*)::int from public.notifications where uid = :buyer and kind = 'order_paid'), 1, 'the buyer is told it arrived');

-- the seller packs it from a copy that lacks the server's own keys ----------------------------------------------
select pg_temp.as_user(:farmer);
select lives_ok($f$select public.put_order((select data - 'paid' - 'paidAt' - 'stockTaken' || '{"status":"findingDriver","commission":0.05,"rev":2}' from public.market_orders where id = 'PAY1'))$f$, 'a packed copy without the server keys is accepted once it is paid');
select pg_temp.as_admin();
select is((select status from public.market_orders where id = 'PAY1'), 'findingDriver', 'drivers can see it');
select is((select data ->> 'paid' from public.market_orders where id = 'PAY1'), 'true', 'and the paid flag is still there');

-- cash on delivery needs no card ---------------------------------------------------------------------------
update public.market_products set data = data || '{"stock": 9}' where id = 'P1';
select pg_temp.as_user(:buyer2);
select lives_ok(format($f$select public.place_order(%L, '1234')$f$, pg_temp.order_json('CASH1', :buyer2, :farmer, '{"method":"cash"}')), 'a cash order is placed');
select is((select data ->> 'paid' from public.market_orders where id = 'CASH1'), 'true', 'and counts as ready to pack');

select * from finish();
rollback;
