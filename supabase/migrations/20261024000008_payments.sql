-- Card payments through Yoco. The server creates the checkout, so the amount is
-- never taken from the phone, and only a signed message from Yoco can turn a
-- membership on.
create table public.payments (
  id text primary key default gen_random_uuid()::text,
  uid text not null,
  kind text not null default 'membership',
  tier text not null,
  amount_cents int not null,
  checkout_id text unique,
  processing_mode text,
  status text not null default 'created' check (status in ('created', 'paid', 'failed')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
alter table public.payments enable row level security;
create policy payments_own on public.payments for select to authenticated using (uid = auth.uid()::text or public.is_admin());
alter publication supabase_realtime add table public.payments;

-- Only the server (service role) may turn a membership on from a payment.
create or replace function public.activate_membership_paid(p_payment text, p_checkout text) returns text
language plpgsql security definer set search_path = public as $$
declare p public.payments;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from public.payments where id = p_payment and checkout_id = p_checkout for update;
  if not found then return 'unknown'; end if;
  if p.status = 'paid' then return 'already'; end if;
  update public.payments set status = 'paid', paid_at = now() where id = p.id;
  update public.memberships
     set status = 'active', started_at = now(), term_ends_at = now() + make_interval(months => term_months), payment_ref = 'yoco:' || p_checkout
   where uid = p.uid and tier = p.tier and status = 'awaiting_payment';
  return 'activated';
end $$;
revoke all on function public.activate_membership_paid(text, text) from public, anon, authenticated;
grant execute on function public.activate_membership_paid(text, text) to service_role;
