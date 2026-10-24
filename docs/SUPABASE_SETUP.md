# Supabase setup

Supabase holds sign-in and every shared table for Nolifa Grow, Nolifa Drop, Nolifa Delivery and the back office. The schema, the security rules and the database tests are all in `supabase/`.

## 1. Try it on this computer (no account needed)

Needs Docker Desktop running.

```bash
supabase start          # first run downloads images, a few minutes
supabase test db        # 176 database checks (pgTAP)
supabase/run_live_tests.sh   # signs in real people and replays what the apps do
```

Build an app against it. The URL and key are printed by `supabase status`.

```bash
flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<ANON_KEY>
```

The iOS simulator reaches `127.0.0.1`. A real phone needs your computer's address on the same wifi instead. Emails (password reset) show up in Mailpit at http://127.0.0.1:54324.

## 2. Create the real project

1. supabase.com, New project. Pick the region closest to your users (Cape Town is not offered, use Europe West or the nearest). Save the database password.
2. Settings, API: copy the **Project URL** and the **anon public key**. The anon key is safe to ship in the apps. Never put the `service_role` key in an app.
3. Link and push the schema:

```bash
supabase login
supabase link --project-ref <your project ref>
supabase db push
```

4. Authentication, Providers, Email: turn on **Confirm email** for launch. Authentication, URL Configuration: set the site URL (the back office address) and add the app deep link when you add one. Under Authentication, Attack protection, turn on CAPTCHA.
5. Authentication, SMTP: add a real mail sender before launch. The built in one is limited to a few emails an hour.

## 3. Build the apps against the real project

The project is `Nolifa Suite` (ref `ysjitrdzraofzfqhbcfp`, eu-north-1). Its URL and public anon key are the build defaults, so a plain `flutter build` already talks to it. The settings below only override that (for example `--dart-define=SUPABASE_URL=` empty keeps an app on the phone alone).

```bash
flutter build ios --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter build appbundle --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...   # back office
```

The back office is static files. Host `backoffice/build/web` anywhere (the current site is on Firebase Hosting at https://nolifa-backoffice.web.app, which still works for static files, or use Netlify or Vercel).

## 4. Give people their roles

People cannot give themselves a role. In the Supabase dashboard, SQL editor (or `psql`), after the person has signed up:

```sql
-- warehouse staff (back office, hub desk, cut orders)
insert into public.staff (uid, name) values ('<user id>', 'Thandi, Durban hub');
-- inspectors who certify the warehouse
insert into public.certifiers (uid, name) values ('<user id>', 'Inspector Dlamini');
-- verified people (can vote on water, report road hazards, confirm cases, deposit stock)
insert into public.verified_users (uid) values ('<user id>');
```

The user id is on Authentication, Users. Roles that live in the sign-in token (set from a trusted machine, never from the app):

```sql
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"utility": true}' where id = '<user id>';  -- water provider
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"mediator": true}' where id = '<user id>'; -- rules on disputes
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"vet": true}' where id = '<user id>';      -- verifies outbreak cases
```

The person signs out and in again to pick up the new token.

Roles that open back office pages (add a row, then they sign in again):

```sql
insert into public.admins (uid) values ('<user id>');   -- applications, memberships, boreholes
insert into public.vets (uid, name, practice) values ('<user id>', 'Dr Naidoo', 'Howick Vet');  -- vet cases
```

Drivers: a driver applies in Nolifa Delivery (ID, selfie, licence, vehicle). An admin opens Back office, Drivers, checks the photos and approves. Until then the driver cannot go online or see any job.

Plans: every farm is on Starter (8 percent commission) until an admin changes it in Back office, Plans, after the payment has cleared.

Turning a membership on: the farmer signs up in the app (status "awaiting payment"). When the first payment clears in the bank, an admin opens Back office, Memberships, and taps "Payment received". That starts the 24 month term.

Borehole discount and the 50 000 litre reserve are set in `public.borehole_config` (member 10 percent and Max 15 percent are placeholders: set your real numbers).

## What stays on you

- Verification: today a person is "verified" only when you add them to `verified_users`. Phone code checks (Supabase supports Twilio) or farm verification can fill that table automatically later.
- Payments: escrow is still bookkeeping inside the app and database. Real money needs a payment partner (see STORE_READINESS.md).
- Order totals are checked in the app, not recomputed on the server yet (listed in SSDLC.md).

## Current state of the cloud project

- Migrations are pushed. The 9 live tests passed against it, then the test data was removed.
- Email confirmation is OFF (`mailer_autoconfirm`) so judges can sign up at once. The built in mail sender allows only a few emails an hour. Before public launch add your own SMTP, then turn confirmation and CAPTCHA on.
- No staff, certifier or verified rows exist yet. Add yours with the SQL in section 4.

## Alerts to staff and vets

Every vet video, vet visit request, borehole request, new membership and new application writes an alert to `public.outbox`. A server function (`supabase/functions/notify`) turns pending alerts into emails. Video links in the emails are private and expire after 7 days. Videos are never attached.

- Who gets them: Back office, Alerts, "Staff alerts go to" and "Vet alerts go to". Both are `attiiweb15@gmail.com` for now.
- The email sender needs a mail key. Until one is set, alerts wait in the outbox and show in Back office, Alerts. To set it:

```bash
supabase secrets set RESEND_API_KEY=re_xxxxx --project-ref ysjitrdzraofzfqhbcfp
```

Then press "Send waiting alerts now" in Back office, Alerts.
- Resend's free plan only sends to the address you signed up with until you verify a domain. That is fine while you are the one receiving.

## Live road incidents (TomTom)

`supabase/functions/traffic` pulls live incidents for Durban, the South Coast, the North Coast, the Midlands and Zululand every 5 minutes (a scheduled job in the database) and stores them in `public.traffic_incidents`. Everyone signed in can read them. Only the function writes.

- The key lives only as a server secret: `supabase secrets set TOMTOM_KEY=... --project-ref ysjitrdzraofzfqhbcfp`. It is never in the apps or the repository.
- TomTom's free tier allows 2 500 requests a day. This uses about 1 440 (5 areas, every 5 minutes).
- In the apps, people see incidents within 25 km of them, each labelled "TomTom" with its age. Serious ones within 15 km also raise a notification while the app is open. Alerts when the app is closed need Apple and Google push, which are not set up yet.
- Only drivers can report hazards. Customers read, they do not report.
