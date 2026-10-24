-- Who looked at a person's ID or selfie. The back office records a row before it
-- opens a verification photo. Staff can read the list; nobody can change or
-- delete it.
create table public.id_photo_views (
  id bigint generated always as identity primary key,
  staff_uid text not null,
  staff_email text,
  bucket text not null,
  path text not null,
  at timestamptz not null default now()
);
alter table public.id_photo_views enable row level security;
create policy id_views_admin on public.id_photo_views for select to authenticated using (public.is_admin());

create or replace function public.log_photo_view(p_bucket text, p_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  if length(coalesce(p_bucket, '')) > 60 or length(coalesce(p_path, '')) > 300 then raise exception 'bad path' using errcode = 'P0001'; end if;
  insert into public.id_photo_views (staff_uid, staff_email, bucket, path)
  values (auth.uid()::text, (select email from auth.users where id = auth.uid()), p_bucket, p_path);
end $$;
grant execute on function public.log_photo_view(text, text) to authenticated;
