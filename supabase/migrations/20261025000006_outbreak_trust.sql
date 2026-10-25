-- Outbreak reports you can trust.
--
-- Anyone signed in can report what they see. The report goes on the map at
-- once, marked unconfirmed. Two verified farms confirm it (confirm_case), and
-- only then are nearby farms alerted. A vet or an agricultural extension
-- officer can then verify it, or reject it so it leaves the map.

-- ───────── Extension officers ─────────
create table if not exists public.extension_officers (
  uid text primary key,
  name text,
  area text,
  added_at timestamptz not null default now()
);
alter table public.extension_officers enable row level security;
drop policy if exists officers_self on public.extension_officers;
create policy officers_self on public.extension_officers for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

create or replace function public.is_officer() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('officer')
    or exists (select 1 from public.extension_officers where uid = auth.uid()::text))
$$;

-- True for the people who may verify or reject an outbreak.
create or replace function public.is_case_verifier() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_vet() or public.is_officer()
$$;
grant execute on function public.is_case_verifier() to authenticated;

-- 'vet', 'officer' or null, so the app knows which buttons to show.
create or replace function public.case_verifier_role() returns text
language sql stable security definer set search_path = public as $$
  select case when public.is_vet() then 'vet' when public.is_officer() then 'officer' end
$$;
grant execute on function public.case_verifier_role() to authenticated;

-- The back office adds an officer by their sign-in email.
create or replace function public.add_extension_officer(p_email text, p_area text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid text; v_name text;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  select id::text, raw_user_meta_data ->> 'name' into v_uid, v_name
    from auth.users where lower(email) = lower(trim(p_email));
  if v_uid is null then raise exception 'No account with that email yet.' using errcode = 'P0001'; end if;
  insert into public.extension_officers (uid, name, area) values (v_uid, v_name, p_area)
    on conflict (uid) do update set area = coalesce(excluded.area, public.extension_officers.area);
end $$;
grant execute on function public.add_extension_officer(text, text) to authenticated;

-- ───────── Verify or reject a case ─────────
create or replace function public.verify_case(p_id text, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  d jsonb;
  role text;
begin
  if public.is_vet() then role := 'vet';
  elsif public.is_officer() then role := 'officer';
  else raise exception 'Only a vet or an extension officer can verify an outbreak.' using errcode = '42501';
  end if;
  select data into d from public.market_cases where id = p_id for update;
  if d is null then raise exception 'That report no longer exists.' using errcode = 'P0001'; end if;
  perform set_config('nolifa.internal', '1', true);
  update public.market_cases set data = d || jsonb_build_object(
      'stage', case when p_ok then 'vetVerified' else 'rejected' end,
      'verifiedBy', auth.uid()::text,
      'verifierRole', role,
      'verifiedAt', (extract(epoch from now()) * 1000)::bigint)
    where id = p_id;
  perform set_config('nolifa.internal', '', true);
end $$;
grant execute on function public.verify_case(text, boolean) to authenticated;

-- ───────── Map sightings ─────────
-- Who sent each sighting, so one account cannot flood the map.
alter table public.outbreaks add column if not exists reporter_id text default auth.uid()::text;

-- Any signed-in person may report; the map shows it as unconfirmed until two
-- verified farms back it. Verification moved from reporting to confirming.
drop policy if exists outbreaks_add on public.outbreaks;
create policy outbreaks_add on public.outbreaks for insert to authenticated with check (
  reporter_id = auth.uid()::text
  and jsonb_typeof(data -> 'lat') = 'number' and jsonb_typeof(data -> 'lng') = 'number'
  and data ->> 'severity' in ('green','orange','red')
  and (data -> 'caseId' is null or jsonb_typeof(data -> 'caseId') = 'string')
  and length(coalesce(data ->> 'disease', '')) between 1 and 120);

create or replace function public.outbreaks_rate_limit() returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if (select count(*) from public.outbreaks
       where reporter_id = new.reporter_id and created_at > now() - interval '1 day') >= 20 then
    raise exception 'You have sent a lot of reports today. Try again tomorrow.' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists a_outbreaks_rate on public.outbreaks;
create trigger a_outbreaks_rate before insert on public.outbreaks
  for each row execute function public.outbreaks_rate_limit();

-- New outbreak cases must be opened by the person reporting them, unconfirmed.
-- (cases_create already checks reporter, stage and confirmations.)
