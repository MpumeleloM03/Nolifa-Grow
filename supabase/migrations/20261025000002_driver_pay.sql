-- Driver pay that follows the work, kept on the server.
--
-- Before: a driver got 80% of the buyer's delivery fee, worked out on their own
-- phone. A 5 km trip paid R12, and nothing on the server recorded what a driver
-- was owed.
--
-- Now:
--   * Pay = R12 per delivery + R2.50 per road km, never under R24. The same
--     formula lives in the Dart package (driver_pay.dart); tests pin both to the
--     same numbers.
--   * The kilometres come from the order but are capped by what the delivery fee
--     could have paid for, so nobody gains by inflating the distance.
--   * The server writes the amount into driver_payouts when the PIN is accepted.
--     The driver can read their own rows and nothing else can write them.
--   * The row is released when the order is released, and cancelled to R0 after a
--     full refund or a driver-conduct dispute.
--   * topup is what Nolifa adds on top of 80% of the buyer's fee.

create or replace function public.driver_job_pay(o jsonb) returns numeric
language sql immutable as $$
  with p as (
    select coalesce((o ->> 'deliveryFee')::numeric, 0) as fee,
           coalesce(nullif((o ->> 'distanceKm')::numeric, 0), 10) as claimed,
           (o ->> 'route') = 'hub' as hub
  ), k as (
    select fee, hub,
      case when hub
        -- A hub order is paid for the last mile only: R35 buys the first 30 km.
        then case when fee > 35 then 30 + (fee - 35) else 15 end
        -- A local trip is never longer than the fee could have bought (a group
        -- buy halves the fee, hence the doubling).
        else least(80, greatest(1, least(claimed, 6 + greatest(0, (fee * 2 - 15) / 2)))) end as km
    from p
  )
  select round(greatest(24, 12 + 2.5 * km)::numeric, 2) from k
$$;

create or replace function public.driver_job_km(o jsonb) returns numeric
language sql immutable as $$
  with p as (
    select coalesce((o ->> 'deliveryFee')::numeric, 0) as fee,
           coalesce(nullif((o ->> 'distanceKm')::numeric, 0), 10) as claimed,
           (o ->> 'route') = 'hub' as hub
  )
  select case when hub then (case when fee > 35 then 30 + (fee - 35) else 15 end)
    else least(80, greatest(1, least(claimed, 6 + greatest(0, (fee * 2 - 15) / 2)))) end from p
$$;

create table public.driver_payouts (
  order_id text primary key,
  driver_id text not null,
  amount numeric(10, 2) not null,
  base numeric(10, 2) not null,
  distance_pay numeric(10, 2) not null,
  minimum_top_up numeric(10, 2) not null default 0,
  topup numeric(10, 2) not null default 0,
  km numeric(6, 1) not null,
  delivery_fee numeric(10, 2) not null,
  state text not null default 'pending' check (state in ('pending', 'released', 'cancelled')),
  created_at timestamptz not null default now(),
  released_at timestamptz
);
create index driver_payouts_driver on public.driver_payouts (driver_id, created_at desc);
alter table public.driver_payouts enable row level security;
create policy driver_payouts_read on public.driver_payouts for select to authenticated
  using (driver_id = auth.uid()::text or public.is_hub_staff() or public.is_admin());
alter publication supabase_realtime add table public.driver_payouts;

-- Writes the payout row for a delivered order. Called only from inside the
-- delivery function, so a driver cannot create or change one.
create or replace function public.record_driver_payout(d jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  km numeric := public.driver_job_km(d);
  distance numeric := round(2.5 * km, 2);
  pay numeric := public.driver_job_pay(d);
  fee numeric := coalesce((d ->> 'deliveryFee')::numeric, 0);
begin
  if public.jnull(d, 'driverId') or coalesce((d ->> 'selfDelivery')::boolean, false) then return; end if;
  insert into public.driver_payouts (order_id, driver_id, amount, base, distance_pay, minimum_top_up, topup, km, delivery_fee)
  values (d ->> 'id', d ->> 'driverId', pay, 12, distance, round(greatest(0, pay - 12 - distance), 2),
          round(greatest(0, pay - fee * 0.8), 2), round(km, 1), fee)
  on conflict (order_id) do nothing;
end $$;
revoke all on function public.record_driver_payout(jsonb) from public, anon, authenticated;

-- deliver_with_pin: as before, and the server notes what the driver earned.
create or replace function public.deliver_with_pin(p_id text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid text := auth.uid()::text;
  d jsonb;
  pin public.order_pins;
  used int;
begin
  select data into d from public.market_orders where id = p_id for update;
  if d is null then raise exception 'no such order'; end if;
  if not (d ->> 'driverId' = v_uid
          or (d ->> 'farmerId' = v_uid and coalesce((d ->> 'selfDelivery')::boolean, false))) then
    raise exception 'This is not your delivery.' using errcode = '42501';
  end if;
  if d ->> 'status' <> 'pickedUp' then raise exception 'Collect the goods first.' using errcode = 'P0001'; end if;
  if not public.jnull(d, 'dispute') then return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0); end if;
  select * into pin from public.order_pins where order_id = p_id for update;
  if not found or pin.attempts >= 3 then return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0); end if;

  perform set_config('nolifa.internal', '1', true);
  if crypt(p_pin, pin.pin_hash) = pin.pin_hash then
    update public.market_orders set data = d || jsonb_build_object(
      'status', 'delivered', 'deliveredAt', public.now_ms(), 'rev', coalesce((d ->> 'rev')::int, 0) + 1) where id = p_id;
    perform public.record_driver_payout(d);
    perform set_config('nolifa.internal', '', true);
    return jsonb_build_object('outcome', 'delivered', 'attemptsLeft', 3);
  end if;
  used := pin.attempts + 1;
  update public.order_pins set attempts = used where order_id = p_id;
  if used >= 3 then
    update public.market_orders set data = d || jsonb_build_object(
      'pinAttempts', used, 'rev', coalesce((d ->> 'rev')::int, 0) + 1,
      'dispute', jsonb_build_object('reason', 'pinLocked', 'stage', 'open', 'outcome', null,
        'note', 'The delivery PIN was entered wrongly 3 times, so the order was locked.',
        'timeline', jsonb_build_array(jsonb_build_object('t', 'The delivery PIN was entered wrongly 3 times, so the order was locked.', 'at', public.now_ms()))))
    where id = p_id;
    perform set_config('nolifa.internal', '', true);
    return jsonb_build_object('outcome', 'locked', 'attemptsLeft', 0);
  end if;
  update public.market_orders set data = d || jsonb_build_object('pinAttempts', used, 'rev', coalesce((d ->> 'rev')::int, 0) + 1) where id = p_id;
  perform set_config('nolifa.internal', '', true);
  return jsonb_build_object('outcome', 'wrong', 'attemptsLeft', 3 - used);
end $$;

-- When the order is released the payout is released; after a full refund or a
-- driver-conduct dispute the driver is not paid.
create or replace function public.driver_payout_follow() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nd jsonb := new.data;
  unpaid boolean;
begin
  if not (nd -> 'released' = 'true'::jsonb) then return new; end if;
  unpaid := nd -> 'dispute' ->> 'outcome' = 'fullRefund' or nd -> 'dispute' ->> 'reason' = 'driverConduct';
  update public.driver_payouts
     set state = case when unpaid then 'cancelled' else 'released' end,
         amount = case when unpaid then 0 else amount end,
         topup = case when unpaid then 0 else topup end,
         released_at = now()
   where order_id = new.id and state = 'pending';
  return new;
end $$;
create trigger z_driver_payout_follow after update on public.market_orders
  for each row when (new.data is distinct from old.data) execute function public.driver_payout_follow();
