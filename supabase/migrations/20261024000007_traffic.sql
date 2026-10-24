-- Live traffic incidents from TomTom, kept fresh by a function every 5 minutes.
-- Everyone signed in can read them. Only the function writes them.
create table public.traffic_incidents (
  id text primary key,
  category int not null default 0,
  magnitude int not null default 0,
  description text not null default '',
  road text not null default '',
  from_place text not null default '',
  to_place text not null default '',
  lat double precision not null,
  lng double precision not null,
  length_m int not null default 0,
  delay_s int,
  starts_at timestamptz,
  ends_at timestamptz,
  area text not null default '',
  seen_at timestamptz not null default now()
);
create index traffic_incidents_area on public.traffic_incidents (area);
alter table public.traffic_incidents enable row level security;
create policy traffic_read on public.traffic_incidents for select to authenticated using (true);
alter publication supabase_realtime add table public.traffic_incidents;

alter table public.notify_config add column traffic_url text;

create or replace function public.run_traffic() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c public.notify_config;
begin
  select * into c from public.notify_config where id = 1;
  if c.traffic_url is null then return; end if;
  perform net.http_post(url := c.traffic_url, headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', c.function_secret), body := '{}'::jsonb);
exception when others then
  null;
end $$;

-- Every 5 minutes. Skipped quietly where the scheduler extension is not there.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('nolifa-traffic', '*/5 * * * *', 'select public.run_traffic()');
exception when others then
  raise notice 'traffic schedule not set: %', sqlerrm;
end $$;
