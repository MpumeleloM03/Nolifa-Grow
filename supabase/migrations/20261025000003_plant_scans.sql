-- Plant.id credits are paid for, so each signed-in person gets a daily allowance
-- of online leaf checks. The plant-id function takes one before it calls out.
-- Past the allowance the app still works: it uses the model on the phone.
create table public.plant_scans (
  uid text not null,
  day date not null default (now() at time zone 'Africa/Johannesburg')::date,
  n int not null default 0,
  primary key (uid, day)
);
alter table public.plant_scans enable row level security;

create or replace function public.plant_scan_take(p_uid text, p_limit int) returns boolean
language plpgsql security definer set search_path = public as $$
declare used int;
begin
  insert into public.plant_scans (uid, n) values (p_uid, 1)
  on conflict (uid, day) do update set n = public.plant_scans.n + 1
  returning n into used;
  if used > p_limit then
    update public.plant_scans set n = p_limit where uid = p_uid and day = (now() at time zone 'Africa/Johannesburg')::date;
    return false;
  end if;
  return true;
end $$;
revoke all on function public.plant_scan_take(text, int) from public, anon, authenticated;
