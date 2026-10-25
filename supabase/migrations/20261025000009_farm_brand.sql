-- Farm logo and store picture.
--
-- A farm uploads both with its application. They live in a public bucket (they
-- are for buyers to see). Once Nolifa approves the farm they are copied into the
-- public farm profile, and Drop, Grow and the back office all show them from there.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('farm-brand', 'farm-brand', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- A farmer writes only in their own folder.
create policy farm_brand_put on storage.objects for insert to authenticated
  with check (bucket_id = 'farm-brand' and (storage.foldername(name))[1] = auth.uid()::text);
create policy farm_brand_del on storage.objects for delete to authenticated
  using (bucket_id = 'farm-brand' and (storage.foldername(name))[1] = auth.uid()::text);

-- The form cannot be sent without them.
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
  foreach k in array array['id_front', 'selfie_with_id', 'land_photo', 'farm_logo', 'farm_banner'] loop
    if not exists (select 1 from public.application_files where uid = v_uid and kind = k) then missing := missing || ('photo:' || k); end if;
  end loop;
  if cardinality(missing) > 0 then
    raise exception 'Still missing: %', array_to_string(missing, ', ') using errcode = 'P0004';
  end if;
  update public.farm_applications set status = 'submitted', submitted_at = now(), updated_at = now(), review_note = '' where uid = v_uid;
end $$;

-- The latest logo or store picture the farm uploaded, as a path in farm-brand.
create or replace function public.brand_path(p_uid text, p_kind text) returns text
language sql stable security definer set search_path = public as $$
  select path from public.application_files where uid = p_uid and kind = p_kind order by created_at desc limit 1
$$;
revoke all on function public.brand_path(text, text) from public, anon, authenticated;

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
      'practices', coalesce(a.data -> 'practices', '{}'::jsonb), 'registered', coalesce(a.data ->> 'regNumber', '') <> '',
      'logo', public.brand_path(p_uid, 'farm_logo'), 'banner', public.brand_path(p_uid, 'farm_banner')))
    on conflict (uid) do update set data = excluded.data, approved_at = now();
  end if;
end $$;

-- An approved farm can change its pictures later. They go live at once.
create or replace function public.set_farm_brand(p_logo text, p_banner text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if not exists (select 1 from public.farm_profiles where uid = v_uid) then
    raise exception 'Your farm is not approved yet. Add the pictures to your application.' using errcode = 'P0001';
  end if;
  if p_logo is not null and (storage.foldername(p_logo))[1] <> v_uid then raise exception 'not your file' using errcode = '42501'; end if;
  if p_banner is not null and (storage.foldername(p_banner))[1] <> v_uid then raise exception 'not your file' using errcode = '42501'; end if;
  update public.farm_profiles
     set data = data || jsonb_strip_nulls(jsonb_build_object('logo', p_logo, 'banner', p_banner))
   where uid = v_uid;
end $$;
grant execute on function public.set_farm_brand(text, text) to authenticated;

-- Everyone who can open the shop sees the pictures change without a restart.
do $$ begin
  alter publication supabase_realtime add table public.farm_profiles;
exception when duplicate_object then null;
end $$;

-- Drop's door carries the pictures with each farm.
create or replace function drop_api.farms() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(f order by f ->> 'farm'), '[]'::jsonb) from (
    select jsonb_build_object(
      'ownerId', p.owner_id,
      'farm', max(p.data ->> 'farm'),
      'logo', (select fp.data ->> 'logo' from public.farm_profiles fp where fp.uid = p.owner_id),
      'banner', (select fp.data ->> 'banner' from public.farm_profiles fp where fp.uid = p.owner_id),
      'products', count(*),
      'inStock', count(*) filter (where coalesce((p.data ->> 'stock')::numeric, 1) > 0 and coalesce((p.data ->> 'available')::boolean, true)),
      'items', jsonb_agg(jsonb_build_object('id', p.id, 'name', p.data ->> 'name', 'price', p.data -> 'price', 'unit', p.data ->> 'unit',
                                            'stock', p.data -> 'stock', 'emoji', p.data ->> 'emoji') order by p.data ->> 'name')) as f
      from public.market_products p
     group by p.owner_id) s
$$;
