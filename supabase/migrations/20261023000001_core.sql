-- Nolifa core: roles, helpers, private profiles, Grow herd data.
-- Every user id is auth.uid()::text so the apps keep their string ids.

create table public.staff (uid text primary key, name text not null default '', added_at timestamptz not null default now());
create table public.certifiers (uid text primary key, name text not null default '', added_at timestamptz not null default now());
create table public.verified_users (uid text primary key, added_at timestamptz not null default now());
alter table public.staff enable row level security;
alter table public.certifiers enable row level security;
alter table public.verified_users enable row level security;

-- A person reads only their own role row. Nobody writes from the apps.
create policy staff_self on public.staff for select to authenticated using (uid = auth.uid()::text);
create policy certifiers_self on public.certifiers for select to authenticated using (uid = auth.uid()::text);
create policy verified_self on public.verified_users for select to authenticated using (uid = auth.uid()::text);

-- Claims live in app_metadata, which only the server can set.
create or replace function public.claim(name text) returns boolean
language sql stable as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> name)::boolean, false)
$$;

create or replace function public.is_verified() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('verified')
    or exists (select 1 from public.verified_users where uid = auth.uid()::text))
$$;

create or replace function public.is_hub_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('hub')
    or exists (select 1 from public.staff where uid = auth.uid()::text))
$$;

create or replace function public.is_certifier() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.claim('certifier')
    or exists (select 1 from public.certifiers where uid = auth.uid()::text))
$$;

create or replace function public.is_mediator() returns boolean
language sql stable as $$ select auth.uid() is not null and public.claim('mediator') $$;
create or replace function public.is_utility() returns boolean
language sql stable as $$ select auth.uid() is not null and public.claim('utility') $$;
create or replace function public.is_vet() returns boolean
language sql stable as $$ select auth.uid() is not null and public.claim('vet') $$;

-- Keys whose values differ between two json documents (missing counts as different from null).
create or replace function public.changed_keys(a jsonb, b jsonb) returns text[]
language sql immutable as $$
  select coalesce(array_agg(k), '{}') from (
    select jsonb_object_keys(coalesce(a, '{}')) as k
    union
    select jsonb_object_keys(coalesce(b, '{}'))
  ) s where (a -> k) is distinct from (b -> k)
$$;

-- True when the key is missing or json null.
create or replace function public.jnull(j jsonb, k text) returns boolean
language sql immutable as $$ select (j -> k) is null or jsonb_typeof(j -> k) = 'null' $$;

create or replace function public.now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

-- ───────── Grow farmer profile ─────────
create table public.users (
  uid text primary key,
  data jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.users enable row level security;
create policy users_read on public.users for select to authenticated using (true);
create policy users_insert on public.users for insert to authenticated with check (uid = auth.uid()::text);
create policy users_update on public.users for update to authenticated using (uid = auth.uid()::text) with check (uid = auth.uid()::text);

-- Herd register and health record, private to their owner.
create table public.cattle (
  uid text not null,
  id text not null,
  data jsonb not null,
  primary key (uid, id)
);
create table public.health_log (
  uid text not null,
  id text not null,
  data jsonb not null,
  primary key (uid, id)
);
alter table public.cattle enable row level security;
alter table public.health_log enable row level security;
create policy cattle_owner on public.cattle for all to authenticated
  using (uid = auth.uid()::text) with check (uid = auth.uid()::text);
create policy health_owner on public.health_log for all to authenticated
  using (uid = auth.uid()::text) with check (uid = auth.uid()::text);

-- Regional chat.
create table public.chat_messages (
  region text not null,
  id text not null,
  uid text not null,
  data jsonb not null,
  primary key (region, id)
);
alter table public.chat_messages enable row level security;
create policy chat_read on public.chat_messages for select to authenticated using (true);
create policy chat_post on public.chat_messages for insert to authenticated with check (
  uid = auth.uid()::text
  and data ->> 'uid' = auth.uid()::text
  and jsonb_typeof(data -> 'text') = 'string'
  and length(data ->> 'text') between 1 and 1000
  and data ->> 'kind' in ('message', 'alert'));
create policy chat_delete on public.chat_messages for delete to authenticated using (uid = auth.uid()::text);

-- Private balances, plan, verification checks and ledger.
create table public.market_profiles (
  uid text primary key,
  state jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.market_profiles enable row level security;
create policy profiles_owner on public.market_profiles for all to authenticated
  using (uid = auth.uid()::text) with check (uid = auth.uid()::text);
