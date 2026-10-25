# Nolifa Grow

**Catch it early. Keep your community fed.**

One Android app that protects farming communities in South Africa. Built for the FNB App of
the Year theme *Climate resilience and essential services*.

When disease or drought hits a farming community, food and water are the first things people
lose. Nolifa Grow catches disease early, warns everyone nearby, and keeps food moving from
local farms to local families.

## One app, three people

Everyone signs in to the same app and is sent to what they use.

| Role | Tabs | What they do |
|---|---|---|
| **Community member** | Diagnose, Outbreaks, Water, Shop, Me | Check a sick plant or animal, see outbreaks and water alerts nearby, buy fresh food from the nearest farm |
| **Farmer** | Diagnose, Outbreaks, Water, Sell, Me | Everything above, plus selling produce and handling orders |
| **Driver** | Jobs, Roads, Earnings, Me | Deliver orders, report flooded or blocked roads, get paid when the buyer gives the delivery PIN |

## What it does

- **AI diagnosis.** Take a photo of a sick plant, or tick an animal's symptoms, and get the disease and what to do. A basic plant check works offline. The app is available in English and isiZulu.
- **Live outbreak map.** Reports show by area (rounded to about 5 km), never at a farm.
  - A new report appears straight away as *unconfirmed*.
  - Nearby farms are alerted once **2 verified farms** confirm it.
  - A **vet or agricultural extension officer** can verify it, or reject it so it leaves the map.
- **Water alerts.** Real dam levels from the Department of Water and Sanitation, and how long supply will last. Households can ask for help together.
- **7-day farm forecast.** Real weather turned into warnings for frost, heat, heavy rain and fungus.
- **Marketplace and delivery.** Farmers sell straight to their community. Payment is held in escrow until the buyer gives the 4-digit delivery PIN.

## Try it

On the sign-in screen, tap **Farmer**, **Community** or **Driver** under *Demo accounts*. The
demo emails and password are shown on that screen.

## Technology

| Part | Built with |
|---|---|
| App | Flutter (Android first), Riverpod |
| Backend | Supabase: sign-in, Postgres, row-level security, realtime, storage, Edge Functions |
| Plant diagnosis | Plant.id API (called from the server) and an on-device TensorFlow Lite model for offline checks |
| Weather | Open-Meteo |
| Dam levels | Department of Water and Sanitation weekly State of Dams (KZN) |
| Maps | OpenStreetMap tiles and Nominatim |
| Road incidents | TomTom Traffic API |
| Payments | Yoco |
| Email | Resend |

API keys live in Supabase Edge Function secrets, never in the app or this repository.
Database rules and server checks are in `supabase/migrations/`. Edge Functions are in
`supabase/functions/`.

## Run it

```bash
git clone https://github.com/MpumeleloM03/Nolifa-Grow.git
cd Nolifa-Grow
flutter pub get
flutter run
```

To build an APK: `flutter build apk --release` (output in `build/app/outputs/flutter-apk/`).

The app connects to the shared Supabase project by default. To use your own, see
`docs/SUPABASE_SETUP.md` and run the migrations in `supabase/migrations/`.

## Security and privacy

- Row-level security on every table. Orders, payouts, confirmations and verification are checked on the server.
- Outbreak locations are rounded to about 5 km. Each account can send at most 20 reports a day.
- Profiles are private, and users can delete their account from the app.
- Data is shared with lenders or insurers only if the farmer switches it on (POPIA).

## Project layout

| Folder | What is in it |
|---|---|
| `lib/` | The app: role-based shell, diagnosis, outbreak map, water, selling, driver screens |
| `packages/ubuntu_core/` | Shared engine: marketplace, water, roads, delivery, translations |
| `supabase/` | Database migrations, Edge Functions and live tests |
| `backoffice/` | Staff web app for verification and approvals |
| `docs/` | Setup, business model and security notes. `APP_DOORS.md` explains the three app doors |
