-- A second factor by email for the accounts that can hurt people if they are
-- taken over: admins, hub staff, certifiers, mediators, vets and water providers.
--
--  * After a password sign-in the person asks for a 6-digit code, which goes to
--    their email. The right code marks that one sign-in session as verified.
--  * Every staff power in the database (is_admin, is_hub_staff, ...) now also
--    needs a verified session. A stolen password alone opens nothing.
--  * Off by default (app_settings.staff_2fa) so the apps and the back office can
--    ship the code screen first. An admin turns it on from the back office.
--  * Someone can be exempted by an admin, with a reason, for test accounts whose
--    mailbox cannot receive mail yet. Exemptions are listed and audited.
--  * Codes are hashed, last 10 minutes, allow 5 tries, and a person can ask for
--    5 a day. The email body holding the code is wiped as soon as it is sent and
--    is never visible in the back office outbox.

create table public.app_settings (
  id int primary key default 1 check (id = 1),
  staff_2fa boolean not null default false
);
insert into public.app_settings default values;
alter table public.app_settings enable row level security;

create table public.second_factor_exempt (
  uid text primary key,
  reason text not null,
  added_by text,
  added_at timestamptz not null default now()
);
alter table public.second_factor_exempt enable row level security;

create table public.login_codes (
  uid text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  tries int not null default 0,
  sends int not null default 1,
  window_start timestamptz not null default now()
);
alter table public.login_codes enable row level security;

create table public.verified_sessions (
  session_id text primary key,
  uid text not null,
  verified_at timestamptz not null default now()
);
alter table public.verified_sessions enable row level security;
-- No policies on any of the four tables: only the functions below touch them.

-- The roles as they were, without the second factor.
create or replace function public.raw_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('admin')
    or exists (select 1 from public.admins where uid = auth.uid()::text))
$$;
create or replace function public.raw_is_hub_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('hub')
    or exists (select 1 from public.staff where uid = auth.uid()::text))
$$;
create or replace function public.raw_is_certifier() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('certifier')
    or exists (select 1 from public.certifiers where uid = auth.uid()::text))
$$;
create or replace function public.raw_is_vet() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('vet')
    or exists (select 1 from public.vets where uid = auth.uid()::text))
$$;

create or replace function public.session_id() returns text
language sql stable as $$ select coalesce(auth.jwt() ->> 'session_id', '') $$;

-- Does this account hold a power that needs the second factor?
create or replace function public.needs_second_factor() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
    and (select staff_2fa from public.app_settings where id = 1)
    and not exists (select 1 from public.second_factor_exempt where uid = auth.uid()::text)
    and (public.raw_is_admin() or public.raw_is_hub_staff() or public.raw_is_certifier() or public.raw_is_vet()
         or public.claim('mediator') or public.claim('utility'))
$$;

create or replace function public.second_factor_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select not public.needs_second_factor()
    or exists (select 1 from public.verified_sessions
               where session_id = public.session_id() and uid = auth.uid()::text
                 and verified_at > now() - interval '30 days')
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.raw_is_admin() and public.second_factor_ok() $$;
create or replace function public.is_hub_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.raw_is_hub_staff() and public.second_factor_ok() $$;
create or replace function public.is_certifier() returns boolean
language sql stable security definer set search_path = public as $$
  select public.raw_is_certifier() and public.second_factor_ok() $$;
create or replace function public.is_vet() returns boolean
language sql stable security definer set search_path = public as $$
  select public.raw_is_vet() and public.second_factor_ok() $$;
create or replace function public.is_mediator() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and public.claim('mediator') and public.second_factor_ok() $$;
create or replace function public.is_utility() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and public.claim('utility') and public.second_factor_ok() $$;

-- What the app asks after sign-in: does this account need a code, and is this
-- session already verified?
create or replace function public.second_factor_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('required', public.needs_second_factor(), 'ok', public.second_factor_ok())
$$;

create or replace function public.request_login_code() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid text := auth.uid()::text;
  v_email text;
  v_code text;
  cur public.login_codes;
begin
  if v_uid is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  if not public.needs_second_factor() then return jsonb_build_object('required', false); end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then raise exception 'This account has no email address.' using errcode = 'P0001'; end if;

  select * into cur from public.login_codes where uid = v_uid;
  if found and cur.window_start > now() - interval '1 day' and cur.sends >= 5 then
    raise exception 'Too many codes today. Try again tomorrow.' using errcode = 'P0001';
  end if;
  if found and cur.expires_at > now() + interval '9 minutes' then
    raise exception 'A code was just sent. Wait a minute before asking again.' using errcode = 'P0001';
  end if;

  v_code := lpad((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');
  insert into public.login_codes (uid, code_hash, expires_at, tries, sends, window_start)
  values (v_uid, crypt(v_code, gen_salt('bf', 6)), now() + interval '10 minutes', 0, 1, now())
  on conflict (uid) do update set
    code_hash = excluded.code_hash, expires_at = excluded.expires_at, tries = 0,
    sends = case when public.login_codes.window_start > now() - interval '1 day' then public.login_codes.sends + 1 else 1 end,
    window_start = case when public.login_codes.window_start > now() - interval '1 day' then public.login_codes.window_start else now() end;

  perform public.queue_alert('login_code', v_email, 'Your Nolifa sign-in code',
    'Your sign-in code is ' || v_code || E'.\nIt works for 10 minutes. If you did not just sign in, change your password now.');
  return jsonb_build_object('required', true, 'sentTo',
    left(v_email, 1) || '***' || substr(v_email, position('@' in v_email)));
end $$;

create or replace function public.verify_login_code(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid text := auth.uid()::text;
  cur public.login_codes;
begin
  if v_uid is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  select * into cur from public.login_codes where uid = v_uid for update;
  if not found or cur.expires_at < now() then return false; end if;
  if cur.tries >= 5 then raise exception 'Too many wrong codes. Ask for a new one.' using errcode = 'P0001'; end if;
  if crypt(coalesce(p_code, ''), cur.code_hash) = cur.code_hash then
    insert into public.verified_sessions (session_id, uid) values (public.session_id(), v_uid)
      on conflict (session_id) do update set verified_at = now(), uid = excluded.uid;
    delete from public.login_codes where uid = v_uid;
    return true;
  end if;
  update public.login_codes set tries = tries + 1 where uid = v_uid;
  return false;
end $$;

-- Admin controls. They use raw_is_admin so turning the switch on cannot lock the
-- admin out of turning it off before they have a code.
create or replace function public.set_staff_2fa(p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  update public.app_settings set staff_2fa = p_on where id = 1;
end $$;

create or replace function public.exempt_from_2fa(p_uid text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  if coalesce(p_reason, '') = '' then raise exception 'Say why.' using errcode = 'P0001'; end if;
  insert into public.second_factor_exempt (uid, reason, added_by) values (p_uid, p_reason, auth.uid()::text)
    on conflict (uid) do update set reason = excluded.reason, added_by = excluded.added_by, added_at = now();
end $$;

create or replace function public.second_factor_overview() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'on', (select staff_2fa from public.app_settings where id = 1),
    'exempt', coalesce((select jsonb_agg(jsonb_build_object('uid', uid, 'reason', reason, 'added', added_at)) from public.second_factor_exempt), '[]'::jsonb))
  end
$$;

-- Old sessions do not pile up.
create or replace function public.prune_second_factor() returns void
language sql security definer set search_path = public as $$
  delete from public.verified_sessions where verified_at < now() - interval '30 days';
  delete from public.login_codes where expires_at < now() - interval '1 day';
$$;
revoke all on function public.prune_second_factor() from public, anon, authenticated;

-- A sign-in code in the outbox is hidden from the back office, and the body is
-- wiped by the sender once the email has gone.
drop policy outbox_admin on public.outbox;
create policy outbox_admin on public.outbox for select to authenticated
  using (public.is_admin() and kind <> 'login_code');

grant execute on function public.second_factor_status(), public.request_login_code(),
  public.verify_login_code(text), public.set_staff_2fa(boolean), public.exempt_from_2fa(text, text),
  public.second_factor_overview() to authenticated;
revoke execute on function public.raw_is_admin(), public.raw_is_hub_staff(), public.raw_is_certifier(),
  public.raw_is_vet(), public.needs_second_factor() from public, anon;
