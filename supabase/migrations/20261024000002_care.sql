-- Daily water and feed ticks. Private to the farm. They are what shows which
-- farms really look after their animals.
create table public.care_log (
  uid text not null,
  id text not null,
  data jsonb not null,
  primary key (uid, id)
);
alter table public.care_log enable row level security;
create policy care_owner on public.care_log for all to authenticated
  using (uid = auth.uid()::text) with check (uid = auth.uid()::text);
alter publication supabase_realtime add table public.care_log;
