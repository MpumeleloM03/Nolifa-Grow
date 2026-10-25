-- Switching a farm plan by card.
--
-- A farm taps a plan, pays through Yoco, and the plan is on the moment Yoco's
-- signed message arrives. Staff can still set a plan by hand. Every change is
-- written to plan_changes so the back office can see who switched and how.

create table public.plan_changes (
  id bigint generated always as identity primary key,
  uid text not null,
  from_plan text not null,
  to_plan text not null,
  source text not null check (source in ('card', 'staff')),
  amount_cents int not null default 0,
  payment_id text,
  at timestamptz not null default now()
);
create index plan_changes_at on public.plan_changes (at desc);
alter table public.plan_changes enable row level security;
create policy plan_changes_read on public.plan_changes for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());
alter publication supabase_realtime add table public.plan_changes;

-- What each plan costs a month, in cents. The phone never says the price.
create or replace function public.plan_price_cents(p_plan text) returns int
language sql immutable as $$
  select case p_plan when 'starter' then 4900 when 'grow' then 9900 when 'coop' then 19900 end
$$;

-- Only Yoco's signed message (through the webhook, as the service role) turns a card payment into a plan.
create or replace function public.activate_plan_paid(p_payment text, p_checkout text) returns text
language plpgsql security definer set search_path = public as $$
declare p public.payments; v_from text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from public.payments where id = p_payment and checkout_id = p_checkout and kind = 'plan' for update;
  if not found then return 'unknown'; end if;
  if p.status = 'paid' then return 'already'; end if;
  if p.tier not in ('starter', 'grow', 'coop') then return 'unknown plan'; end if;
  update public.payments set status = 'paid', paid_at = now() where id = p.id;
  select coalesce((select plan from public.seller_plans where uid = p.uid), 'starter') into v_from;
  insert into public.seller_plans (uid, plan) values (p.uid, p.tier)
  on conflict (uid) do update set plan = excluded.plan, updated_at = now();
  insert into public.plan_changes (uid, from_plan, to_plan, source, amount_cents, payment_id) values (p.uid, v_from, p.tier, 'card', p.amount_cents, p.id);
  return 'activated';
end $$;
revoke all on function public.activate_plan_paid(text, text) from public, anon, authenticated;
grant execute on function public.activate_plan_paid(text, text) to service_role;

-- A staff change is logged too.
create or replace function public.set_seller_plan(p_uid text, p_plan text) returns void
language plpgsql security definer set search_path = public as $$
declare v_from text;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  select coalesce((select plan from public.seller_plans where uid = p_uid), 'starter') into v_from;
  insert into public.seller_plans (uid, plan) values (p_uid, p_plan)
  on conflict (uid) do update set plan = excluded.plan, updated_at = now();
  if v_from is distinct from p_plan then
    insert into public.plan_changes (uid, from_plan, to_plan, source) values (p_uid, v_from, p_plan, 'staff');
  end if;
end $$;
