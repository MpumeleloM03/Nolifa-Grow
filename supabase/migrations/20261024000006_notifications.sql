-- Alerts for staff and vets. Every request that needs a person writes one row
-- here. A small server function turns pending rows into emails. If no mail key
-- is set the rows simply wait, and the back office shows them either way.

create table public.notify_config (
  id int primary key default 1 check (id = 1),
  staff_email text,
  vet_email text,
  function_url text,
  function_secret text
);
insert into public.notify_config default values;
alter table public.notify_config enable row level security;
-- No policies: only the functions below read it.

create table public.outbox (
  id bigint generated always as identity primary key,
  kind text not null,
  to_email text,
  subject text not null,
  body text not null,
  link_bucket text,
  link_path text,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.outbox enable row level security;
create policy outbox_admin on public.outbox for select to authenticated using (public.is_admin());
alter publication supabase_realtime add table public.outbox;

create or replace function public.set_notify_config(p_staff text, p_vet text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  update public.notify_config set staff_email = nullif(p_staff, ''), vet_email = nullif(p_vet, '') where id = 1;
end $$;

create or replace function public.get_notify_config() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin()
    then (select jsonb_build_object('staff_email', staff_email, 'vet_email', vet_email, 'sending', function_url is not null) from public.notify_config where id = 1)
  end
$$;

-- Wakes the sender. It does nothing until a function address has been stored.
create or replace function public.kick_outbox() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c public.notify_config;
begin
  select * into c from public.notify_config where id = 1;
  if c.function_url is null then return; end if;
  begin
    perform net.http_post(url := c.function_url, headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', c.function_secret), body := '{}'::jsonb);
  exception when others then
    null; -- a failed wake-up never blocks the farmer's request
  end;
end $$;

create or replace function public.kick_outbox_now() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  perform public.kick_outbox();
end $$;

create or replace function public.queue_alert(p_kind text, p_to text, p_subject text, p_body text, p_bucket text default null, p_path text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.outbox (kind, to_email, subject, body, link_bucket, link_path) values (p_kind, p_to, p_subject, p_body, p_bucket, p_path);
  perform public.kick_outbox();
end $$;

create or replace function public.person_line(p_uid text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select data ->> 'name' from public.users where uid = p_uid), 'A Nolifa user')
      || ' (' || coalesce((select data ->> 'region' from public.users where uid = p_uid), 'region not given') || ')'
$$;

-- A farmer sent a video: the vet gets the case and a private link to the video.
create or replace function public.alert_vet_video() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.consults; v_to text;
begin
  select * into c from public.consults where id = new.consult_id;
  select vet_email into v_to from public.notify_config where id = 1;
  perform public.queue_alert('vet_video', v_to,
    'New vet video: ' || c.title,
    'From ' || public.person_line(c.farmer_id) || E'\nAnimal: ' || coalesce(nullif(c.animal_label, ''), c.species, 'not named')
      || E'\nProvince: ' || c.province || E'\nMembership: ' || public.membership_tier(c.farmer_id)
      || E'\nVideo length: ' || new.duration_s || E' seconds\n\n' || coalesce(nullif(c.description, ''), '(no description)')
      || E'\n\nOpen the case in the Nolifa back office, Vet cases, to write the diagnosis.',
    'consult-videos', new.path);
  return new;
end $$;
create trigger t_alert_vet_video after insert on public.consult_videos for each row execute function public.alert_vet_video();

create or replace function public.alert_vet_visit() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_to text;
begin
  if new.status = 'visit_requested' and old.status is distinct from 'visit_requested' then
    select vet_email into v_to from public.notify_config where id = 1;
    perform public.queue_alert('vet_visit', v_to, 'Farm visit requested: ' || new.title,
      'From ' || public.person_line(new.farmer_id) || E'\nPreferred day: ' || coalesce(new.visit ->> 'preferred', '?')
        || E'\nNotes: ' || coalesce(new.visit ->> 'notes', '') || E'\n\nBook a day in the back office, Vet cases.');
  end if;
  return new;
end $$;
create trigger t_alert_vet_visit after update on public.consults for each row execute function public.alert_vet_visit();

create or replace function public.alert_borehole() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_to text;
begin
  select staff_email into v_to from public.notify_config where id = 1;
  perform public.queue_alert('borehole', v_to, 'Borehole request: ' || new.purpose,
    'From ' || public.person_line(new.uid) || E'\nMembership: ' || new.tier || ' (' || new.discount_pct || E'% off)'
      || E'\nWhere: ' || new.lat || ', ' || new.lng || E'\nDirections: ' || new.address || E'\nPhone: ' || new.contact_phone
      || E'\nNotes: ' || new.notes || E'\n\nQuote it in the back office, Boreholes.');
  return new;
end $$;
create trigger t_alert_borehole after insert on public.borehole_requests for each row execute function public.alert_borehole();

create or replace function public.alert_membership() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_to text;
begin
  if new.status = 'awaiting_payment' and (tg_op = 'INSERT' or old.status is distinct from 'awaiting_payment') then
    select staff_email into v_to from public.notify_config where id = 1;
    perform public.queue_alert('membership', v_to, 'New membership waiting for payment',
      public.person_line(new.uid) || ' joined as ' || new.tier || ' at R' || new.monthly_price || E' a month for 24 months.\n\nTurn it on in the back office, Memberships, once the payment clears.');
  end if;
  return new;
end $$;
create trigger t_alert_membership after insert or update on public.memberships for each row execute function public.alert_membership();

create or replace function public.alert_application() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_to text; v_what text;
begin
  if new.status = 'submitted' and old.status is distinct from 'submitted' then
    select staff_email into v_to from public.notify_config where id = 1;
    v_what := case tg_table_name when 'driver_applications' then 'driver' else 'farm' end;
    perform public.queue_alert(v_what || '_application', v_to, 'New ' || v_what || ' application to review',
      public.person_line(new.uid) || E' sent an application.\n\nOpen the ID photo and the selfie in the back office and compare them before approving.');
  end if;
  return new;
end $$;
create trigger t_alert_farm_app after update on public.farm_applications for each row execute function public.alert_application();
create trigger t_alert_driver_app after update on public.driver_applications for each row execute function public.alert_application();
