-- Memberships, vet consults, farm verification and boreholes.
-- Every entitlement (video quota, vet visit, drill discount) is decided here,
-- never in the app.

create table public.admins (uid text primary key, added_at timestamptz not null default now());
create table public.vets (
  uid text primary key,
  name text not null default '',
  practice text not null default '',
  provinces text[] not null default '{KwaZulu-Natal}',
  added_at timestamptz not null default now()
);
-- Provinces where Nolifa has a partner vet who can visit a farm. KZN only for now.
create table public.vet_partner_provinces (province text primary key);
insert into public.vet_partner_provinces values ('KwaZulu-Natal');
alter table public.admins enable row level security;
alter table public.vets enable row level security;
alter table public.vet_partner_provinces enable row level security;
create policy admins_self on public.admins for select to authenticated using (uid = auth.uid()::text);
create policy vets_self on public.vets for select to authenticated using (uid = auth.uid()::text);
create policy partner_read on public.vet_partner_provinces for select to authenticated using (true);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('admin')
    or exists (select 1 from public.admins where uid = auth.uid()::text))
$$;

-- A vet is someone in the vets table, or carrying the vet claim.
create or replace function public.is_vet() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('vet')
    or exists (select 1 from public.vets where uid = auth.uid()::text))
$$;

-- ───────── Memberships ─────────
create table public.memberships (
  uid text primary key,
  tier text not null check (tier in ('member', 'max')),
  status text not null default 'awaiting_payment' check (status in ('awaiting_payment', 'active', 'ended')),
  monthly_price int not null,
  term_months int not null default 24 check (term_months >= 24),
  accepted_terms_at timestamptz not null,
  started_at timestamptz,
  term_ends_at timestamptz,
  payment_ref text,
  created_at timestamptz not null default now()
);
alter table public.memberships enable row level security;
create policy memberships_own on public.memberships for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

create or replace function public.membership_tier(p_uid text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select tier from public.memberships where uid = p_uid and status = 'active'), 'none')
$$;

-- A person signs up. Nothing is active until payment is confirmed.
create or replace function public.join_membership(p_tier text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  cur public.memberships;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if p_tier not in ('member', 'max') then raise exception 'unknown plan'; end if;
  select * into cur from public.memberships where uid = v_uid;
  if found and cur.status = 'active' then
    raise exception 'You already have an active membership. Ask Nolifa to change it.' using errcode = 'P0001';
  end if;
  insert into public.memberships (uid, tier, status, monthly_price, term_months, accepted_terms_at)
  values (v_uid, p_tier, 'awaiting_payment', case p_tier when 'max' then 7000 else 3000 end, 24, now())
  on conflict (uid) do update
    set tier = excluded.tier, status = 'awaiting_payment', monthly_price = excluded.monthly_price,
        term_months = 24, accepted_terms_at = now(), payment_ref = null, started_at = null, term_ends_at = null;
end $$;

-- Staff turn a membership on once the first payment has cleared.
create or replace function public.activate_membership(p_uid text, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  update public.memberships
     set status = 'active', started_at = now(), term_ends_at = now() + make_interval(months => term_months), payment_ref = p_ref
   where uid = p_uid and status = 'awaiting_payment';
  if not found then raise exception 'no membership waiting for payment'; end if;
end $$;

-- ───────── Province of a farm ─────────
create table public.farm_applications (
  uid text primary key,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'needs_info', 'approved', 'rejected')),
  data jsonb not null default '{}',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by text,
  review_note text not null default '',
  updated_at timestamptz not null default now()
);
create table public.application_files (
  id text primary key default gen_random_uuid()::text,
  uid text not null,
  kind text not null,
  path text not null,
  created_at timestamptz not null default now()
);
alter table public.farm_applications enable row level security;
alter table public.application_files enable row level security;

create or replace function public.farm_province(p_uid text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    nullif((select data ->> 'province' from public.farm_applications where uid = p_uid), ''),
    case when (select data ->> 'region' from public.users where uid = p_uid) in
      ('Greater Durban', 'KZN Midlands', 'North Coast', 'South Coast', 'Zululand', 'Northern KZN')
      then 'KwaZulu-Natal' end,
    'Unknown')
$$;

-- ───────── Vet consults ─────────
create table public.consults (
  id text primary key default gen_random_uuid()::text,
  farmer_id text not null,
  province text not null default 'Unknown',
  animal_id text,
  animal_label text not null default '',
  species text not null default '',
  title text not null check (length(title) between 3 and 120),
  description text not null default '' check (length(description) <= 2000),
  kind text not null default 'video' check (kind in ('video', 'onsite')),
  status text not null default 'open' check (status in ('open', 'in_review', 'answered', 'visit_requested', 'visit_booked', 'closed')),
  assigned_vet text,
  diagnosis jsonb,
  visit jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index consults_farmer on public.consults (farmer_id, created_at desc);
create table public.consult_videos (
  id text primary key default gen_random_uuid()::text,
  consult_id text not null references public.consults (id) on delete cascade,
  farmer_id text not null,
  path text not null,
  duration_s int not null check (duration_s between 1 and 120),
  bytes bigint not null default 0,
  created_at timestamptz not null default now()
);
create table public.consult_messages (
  id text primary key default gen_random_uuid()::text,
  consult_id text not null references public.consults (id) on delete cascade,
  sender text not null,
  role text not null check (role in ('farmer', 'vet')),
  body text not null check (length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.consults enable row level security;
alter table public.consult_videos enable row level security;
alter table public.consult_messages enable row level security;

create policy consults_read on public.consults for select to authenticated
  using (farmer_id = auth.uid()::text
    or (public.is_vet() and (province = any (coalesce((select provinces from public.vets where uid = auth.uid()::text), '{KwaZulu-Natal}'))
        or assigned_vet = auth.uid()::text)));
create policy videos_read on public.consult_videos for select to authenticated
  using (farmer_id = auth.uid()::text or public.is_vet());
create policy messages_read on public.consult_messages for select to authenticated
  using (exists (select 1 from public.consults c where c.id = consult_id
    and (c.farmer_id = auth.uid()::text or public.is_vet())));

create or replace function public.video_quota(p_tier text) returns int
language sql immutable as $$ select case p_tier when 'max' then 15 when 'member' then 4 else 0 end $$;

-- A farmer opens a case. Needs an active membership.
create or replace function public.open_consult(p_title text, p_description text, p_animal_id text, p_animal_label text, p_species text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_id text;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if public.membership_tier(v_uid) = 'none' then
    raise exception 'Vet video consults need an active Nolifa membership.' using errcode = '42501';
  end if;
  insert into public.consults (farmer_id, province, animal_id, animal_label, species, title, description)
  values (v_uid, public.farm_province(v_uid), p_animal_id, coalesce(p_animal_label, ''), coalesce(p_species, ''), p_title, coalesce(p_description, ''))
  returning id into v_id;
  return v_id;
end $$;

-- The video row is only accepted inside the plan: 2 minutes each, 4 a month for
-- members, 15 a month for Max.
create or replace function public.consult_videos_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_tier text := public.membership_tier(new.farmer_id);
  used int;
begin
  if new.farmer_id <> auth.uid()::text then raise exception 'not your case' using errcode = '42501'; end if;
  if not exists (select 1 from public.consults where id = new.consult_id and farmer_id = new.farmer_id and status <> 'closed') then
    raise exception 'not your case' using errcode = '42501';
  end if;
  if v_tier = 'none' then raise exception 'Vet video consults need an active Nolifa membership.' using errcode = '42501'; end if;
  select count(*) into used from public.consult_videos
    where farmer_id = new.farmer_id and created_at >= date_trunc('month', now());
  if used >= public.video_quota(v_tier) then
    raise exception 'You have used all % videos for this month.', public.video_quota(v_tier) using errcode = 'P0002';
  end if;
  return new;
end $$;
create trigger b_consult_videos_guard before insert on public.consult_videos
  for each row execute function public.consult_videos_guard();
create policy videos_add on public.consult_videos for insert to authenticated with check (farmer_id = auth.uid()::text);

-- How many videos the signed-in farmer has left this month.
create or replace function public.videos_left() returns int
language sql stable security definer set search_path = public as $$
  select greatest(0, public.video_quota(public.membership_tier(auth.uid()::text))
    - (select count(*)::int from public.consult_videos
        where farmer_id = auth.uid()::text and created_at >= date_trunc('month', now())))
$$;

-- Chat between the farmer and the vet.
create or replace function public.send_consult_message(p_consult text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  c public.consults;
  v_role text;
begin
  select * into c from public.consults where id = p_consult;
  if not found then raise exception 'no such case'; end if;
  if c.status = 'closed' then raise exception 'This case is closed.'; end if;
  if c.farmer_id = v_uid then
    if public.membership_tier(v_uid) = 'none' then raise exception 'Chat needs an active membership.' using errcode = '42501'; end if;
    v_role := 'farmer';
  elsif public.is_vet() then
    v_role := 'vet';
    update public.consults set assigned_vet = coalesce(assigned_vet, v_uid), status = case when status = 'open' then 'in_review' else status end, updated_at = now() where id = p_consult;
  else
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.consult_messages (consult_id, sender, role, body) values (p_consult, v_uid, v_role, p_body);
end $$;

-- The vet's written diagnosis: what, why, what to do and how it helps.
create or replace function public.vet_answer(p_consult text, p_diagnosis jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_vet() then raise exception 'vets only' using errcode = '42501'; end if;
  if coalesce(p_diagnosis ->> 'suspected', '') = '' or coalesce(p_diagnosis ->> 'why', '') = ''
     or coalesce(p_diagnosis ->> 'remedy', '') = '' or coalesce(p_diagnosis ->> 'howItHelps', '') = '' then
    raise exception 'A diagnosis needs what it is, why, the remedy and how it helps.';
  end if;
  update public.consults
     set diagnosis = p_diagnosis || jsonb_build_object('vet', auth.uid()::text, 'at', public.now_ms()),
         assigned_vet = coalesce(assigned_vet, auth.uid()::text),
         status = case when status in ('visit_requested', 'visit_booked') then status else 'answered' end,
         updated_at = now()
   where id = p_consult;
end $$;

-- On-site visits: Max members, in a province with a partner vet.
create or replace function public.request_vet_visit(p_consult text, p_preferred date, p_notes text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  c public.consults;
begin
  select * into c from public.consults where id = p_consult and farmer_id = v_uid;
  if not found then raise exception 'not your case' using errcode = '42501'; end if;
  if public.membership_tier(v_uid) <> 'max' then
    raise exception 'On-site vet visits are part of the Max membership.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.vet_partner_provinces where province = c.province) then
    raise exception 'We do not have a partner vet in your area yet. Right now we cover KwaZulu-Natal.' using errcode = 'P0003';
  end if;
  update public.consults
     set status = 'visit_requested', kind = 'onsite',
         visit = jsonb_build_object('preferred', p_preferred, 'notes', coalesce(p_notes, ''), 'requestedAt', public.now_ms()),
         updated_at = now()
   where id = p_consult;
end $$;

create or replace function public.book_vet_visit(p_consult text, p_on date, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_vet() then raise exception 'vets only' using errcode = '42501'; end if;
  update public.consults
     set status = 'visit_booked', assigned_vet = coalesce(assigned_vet, auth.uid()::text),
         visit = coalesce(visit, '{}'::jsonb) || jsonb_build_object('bookedFor', p_on, 'vetNote', coalesce(p_note, ''), 'bookedBy', auth.uid()::text),
         updated_at = now()
   where id = p_consult and status in ('visit_requested', 'visit_booked');
end $$;

create or replace function public.close_consult(p_consult text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.consults set status = 'closed', updated_at = now()
   where id = p_consult and (farmer_id = auth.uid()::text or public.is_vet());
end $$;

-- ───────── Storage for videos and verification photos ─────────
insert into storage.buckets (id, name, public, file_size_limit)
values ('consult-videos', 'consult-videos', false, 262144000), ('verification', 'verification', false, 15728640)
on conflict (id) do nothing;

create policy consult_videos_put on storage.objects for insert to authenticated
  with check (bucket_id = 'consult-videos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy consult_videos_get on storage.objects for select to authenticated
  using (bucket_id = 'consult-videos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_vet()));
create policy verification_put on storage.objects for insert to authenticated
  with check (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text);
create policy verification_get on storage.objects for select to authenticated
  using (bucket_id = 'verification' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy verification_del on storage.objects for delete to authenticated
  using (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text
    and exists (select 1 from public.farm_applications a where a.uid = auth.uid()::text and a.status in ('draft', 'needs_info')));

-- ───────── Farm verification ─────────
create policy applications_read on public.farm_applications for select to authenticated
  using (uid = auth.uid()::text or public.is_admin() or public.is_vet());
create policy files_read on public.application_files for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

-- The farmer saves a draft. Once submitted it can only change if staff ask for more.
create or replace function public.save_application(p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text; cur public.farm_applications;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  select * into cur from public.farm_applications where uid = v_uid;
  if found and cur.status in ('submitted', 'approved') then
    raise exception 'This application is already with Nolifa.' using errcode = 'P0001';
  end if;
  insert into public.farm_applications (uid, data) values (v_uid, p_data)
  on conflict (uid) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.add_application_file(p_kind text, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if (storage.foldername(p_path))[1] <> v_uid then raise exception 'not your file' using errcode = '42501'; end if;
  delete from public.application_files where uid = v_uid and kind = p_kind and p_kind not in ('certificate', 'land_photo');
  insert into public.application_files (uid, kind, path) values (v_uid, p_kind, p_path);
end $$;

create or replace function public.submit_application() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  a public.farm_applications;
  missing text[] := '{}';
  k text;
begin
  select * into a from public.farm_applications where uid = v_uid;
  if not found then raise exception 'Fill in the form first.'; end if;
  if a.status in ('submitted', 'approved') then raise exception 'Already with Nolifa.' using errcode = 'P0001'; end if;
  foreach k in array array['fullName', 'idNumber', 'phone', 'farmName', 'province', 'lat', 'lng', 'sizeHa', 'farmKind', 'consent'] loop
    if coalesce(a.data ->> k, '') in ('', 'null', 'false') then missing := missing || k; end if;
  end loop;
  foreach k in array array['id_front', 'selfie_with_id', 'land_photo'] loop
    if not exists (select 1 from public.application_files where uid = v_uid and kind = k) then missing := missing || ('photo:' || k); end if;
  end loop;
  if cardinality(missing) > 0 then
    raise exception 'Still missing: %', array_to_string(missing, ', ') using errcode = 'P0004';
  end if;
  update public.farm_applications set status = 'submitted', submitted_at = now(), updated_at = now(), review_note = '' where uid = v_uid;
end $$;

-- A public face for approved farms. Only fields that are safe to show buyers.
create table public.farm_profiles (
  uid text primary key,
  data jsonb not null,
  approved_at timestamptz not null default now()
);
alter table public.farm_profiles enable row level security;
create policy farm_profiles_read on public.farm_profiles for select to authenticated using (true);

create or replace function public.review_application(p_uid text, p_decision text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.farm_applications;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  if p_decision not in ('approved', 'rejected', 'needs_info') then raise exception 'unknown decision'; end if;
  if p_decision <> 'approved' and coalesce(p_note, '') = '' then raise exception 'Say why, so the farmer knows what to fix.'; end if;
  select * into a from public.farm_applications where uid = p_uid and status = 'submitted';
  if not found then raise exception 'That application is not waiting for review.'; end if;
  update public.farm_applications
     set status = p_decision, reviewed_at = now(), reviewed_by = auth.uid()::text, review_note = coalesce(p_note, ''), updated_at = now()
   where uid = p_uid;
  if p_decision = 'approved' then
    insert into public.verified_users (uid) values (p_uid) on conflict do nothing;
    insert into public.farm_profiles (uid, data) values (p_uid, jsonb_build_object(
      'farmName', a.data ->> 'farmName', 'province', a.data ->> 'province', 'town', a.data ->> 'town',
      'farmKind', a.data ->> 'farmKind', 'sizeHa', a.data -> 'sizeHa', 'products', coalesce(a.data -> 'products', '[]'::jsonb),
      'practices', coalesce(a.data -> 'practices', '{}'::jsonb), 'registered', coalesce(a.data ->> 'regNumber', '') <> ''))
    on conflict (uid) do update set data = excluded.data, approved_at = now();
  end if;
end $$;

-- ───────── Boreholes ─────────
create table public.borehole_config (
  id int primary key default 1 check (id = 1),
  member_discount_pct int not null default 10,
  max_discount_pct int not null default 15,
  reserve_litres int not null default 50000
);
insert into public.borehole_config default values;
alter table public.borehole_config enable row level security;
create policy borehole_config_read on public.borehole_config for select to authenticated using (true);

create table public.borehole_requests (
  id text primary key default gen_random_uuid()::text,
  uid text not null,
  purpose text not null check (purpose in ('farm', 'community')),
  lat double precision not null,
  lng double precision not null,
  address text not null default '',
  contact_phone text not null default '',
  notes text not null default '',
  tier text not null default 'none',
  discount_pct int not null default 0,
  reserve_litres int not null,
  status text not null default 'requested' check (status in ('requested', 'quoted', 'accepted', 'scheduled', 'drilled', 'cancelled')),
  standard_quote int,
  final_quote int,
  created_at timestamptz not null default now()
);
alter table public.borehole_requests enable row level security;
create policy borehole_read on public.borehole_requests for select to authenticated
  using (uid = auth.uid()::text or public.is_admin());

create or replace function public.request_borehole(p_purpose text, p_lat double precision, p_lng double precision, p_address text, p_phone text, p_notes text, p_agree_reserve boolean)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_tier text;
  cfg public.borehole_config;
  v_id text;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if not coalesce(p_agree_reserve, false) then
    raise exception 'You need to agree to keep the water reserve for Nolifa.' using errcode = 'P0001';
  end if;
  select * into cfg from public.borehole_config where id = 1;
  v_tier := public.membership_tier(v_uid);
  insert into public.borehole_requests (uid, purpose, lat, lng, address, contact_phone, notes, tier, discount_pct, reserve_litres)
  values (v_uid, p_purpose, p_lat, p_lng, coalesce(p_address, ''), coalesce(p_phone, ''), coalesce(p_notes, ''), v_tier,
          case v_tier when 'max' then cfg.max_discount_pct when 'member' then cfg.member_discount_pct else 0 end,
          cfg.reserve_litres)
  returning id into v_id;
  return v_id;
end $$;

-- Staff quote the standard price; the member discount is applied for them.
create or replace function public.quote_borehole(p_id text, p_standard int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  update public.borehole_requests
     set standard_quote = p_standard, final_quote = round(p_standard * (100 - discount_pct) / 100.0), status = 'quoted'
   where id = p_id and status in ('requested', 'quoted');
end $$;

create or replace function public.accept_borehole_quote(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.borehole_requests set status = 'accepted' where id = p_id and uid = auth.uid()::text and status = 'quoted';
  if not found then raise exception 'There is no quote to accept.'; end if;
end $$;

-- Water Nolifa may collect from each Nolifa drilled borehole, for communities in need.
create table public.water_reserves (
  id text primary key default gen_random_uuid()::text,
  borehole_id text references public.borehole_requests (id),
  owner_uid text not null,
  lat double precision not null,
  lng double precision not null,
  address text not null default '',
  contact_phone text not null default '',
  litres_reserved int not null,
  litres_collected int not null default 0,
  created_at timestamptz not null default now()
);
create table public.reserve_collections (
  id text primary key default gen_random_uuid()::text,
  reserve_id text not null references public.water_reserves (id),
  litres int not null check (litres > 0),
  note text not null default '',
  collected_by text not null,
  created_at timestamptz not null default now()
);
alter table public.water_reserves enable row level security;
alter table public.reserve_collections enable row level security;
create policy reserves_read on public.water_reserves for select to authenticated
  using (owner_uid = auth.uid()::text or public.is_admin() or public.is_hub_staff());
create policy collections_read on public.reserve_collections for select to authenticated
  using (public.is_admin() or public.is_hub_staff());

create or replace function public.mark_borehole_drilled(p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.borehole_requests;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  select * into b from public.borehole_requests where id = p_id and status in ('accepted', 'scheduled');
  if not found then raise exception 'That borehole is not ready to mark as drilled.'; end if;
  update public.borehole_requests set status = 'drilled' where id = p_id;
  insert into public.water_reserves (borehole_id, owner_uid, lat, lng, address, contact_phone, litres_reserved)
  values (b.id, b.uid, b.lat, b.lng, b.address, b.contact_phone, b.reserve_litres);
end $$;

create or replace function public.log_collection(p_reserve text, p_litres int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.water_reserves;
begin
  if not (public.is_admin() or public.is_hub_staff()) then raise exception 'staff only' using errcode = '42501'; end if;
  select * into r from public.water_reserves where id = p_reserve for update;
  if not found then raise exception 'no such reserve'; end if;
  if r.litres_collected + p_litres > r.litres_reserved then
    raise exception 'Only % litres are left in this reserve.', r.litres_reserved - r.litres_collected;
  end if;
  update public.water_reserves set litres_collected = litres_collected + p_litres where id = p_reserve;
  insert into public.reserve_collections (reserve_id, litres, note, collected_by) values (p_reserve, p_litres, coalesce(p_note, ''), auth.uid()::text);
end $$;

alter publication supabase_realtime add table
  public.memberships, public.consults, public.consult_messages, public.farm_applications,
  public.borehole_requests, public.water_reserves;
