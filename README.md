# Nolifa Grow

**Catch it early. Keep your community fed.**

One app (Android and iOS) that protects farming communities in South Africa. Built for the FNB App of
the Year theme *Climate resilience and essential services*.

When disease or drought hits a farming community, food and water are the first things people
lose. Nolifa Grow catches disease early, warns everyone nearby, and keeps food moving from
local farms to local families.

> Four apps share one backend: **Nolifa Grow** (this app, everything in one), a farmers-only edition of the same code, Nolifa Drop and Nolifa Delivery. See `docs/APPS.md`.

## The four apps

One backend, four apps. Every demo login below works in all of them.

| App | For | What it does |
|---|---|---|
| **Nolifa Grow** | Everyone | The ecosystem in one app. Farmers, households and drivers each land on what they use. |
| **Nolifa Grow (farmers edition)** | Farmers | Crop and livestock health, outbreak map, water, stock, selling, truck hire. |
| **Nolifa Drop** | Households | Buy fresh food from nearby farms, pay, follow the driver live, get a PIN for delivery. |
| **Nolifa Delivery** | Drivers | Take jobs, navigate, report road hazards, deliver with the buyer's PIN, get paid per delivery. |

Nolifa Grow and its farmers edition are two builds of this repo (`lib/main.dart`, `lib/main_grow.dart`). Drop and Delivery are separate Flutter projects that use the same `packages/ubuntu_core` engine and the same Supabase project. See `docs/APPS.md`.

### Who sees what in Nolifa Grow

| Role | Tabs | What they do |
|---|---|---|
| **Community member** | Water, Shop, Me | See the water radar and real dam levels, ask for water help, buy from nearby farms and follow the driver on a map |
| **Farmer** | Diagnose, Outbreaks, Water, Sell, Me | Scan crops, check animals, send a video to a vet, report and confirm outbreaks, manage stock and warehouse temperature, hire a truck, pack and dispatch orders |
| **Driver** | Jobs, Roads, Earnings, Me | See packed orders, deliver, report road hazards, get paid |

## Universal demo login (all four apps and the back office)

One email and one password open everything:

| | |
|---|---|
| Email | `all@demo.nolifa.co.za` |
| Password | `NolifaDemo1` |

This one account is a verified farmer (Fatboy Butcheries, on the Grow plan, stock listed), a verified driver, a customer who can order, and back office staff and certifier. Use it in Nolifa, Nolifa Grow, Nolifa Drop, Nolifa Delivery and the back office at https://nolifa-backoffice.web.app .

In Nolifa and Nolifa Grow, open **Me** and use the **Farmer | Driver** tabs at the top to switch sides.

Two more accounts are there for the customer view and a driver-only view (same password): `community@demo.nolifa.co.za` and `driver@demo.nolifa.co.za`. The **Farmer / Community / Driver** buttons on the sign-in screen use `all@demo.nolifa.co.za`, `community@demo.nolifa.co.za` and `driver@demo.nolifa.co.za`.

These are demo accounts on a demo database. Payments run in Yoco test mode. Anything you do with them is visible to everyone using them.

## What it does

- **AI diagnosis.** Photograph a sick plant, or tick an animal's symptoms. You get the disease and what to do. A basic plant check works offline. English and isiZulu.
- **Vets.** A farmer films a sick animal and a vet answers, and can book a visit.
- **Live outbreak map.** Reports show by area (about 5 km), never at a farm. Nearby farms are alerted once 2 verified farms confirm. A vet or extension officer can verify or reject.
- **Water.** Real dam levels (Department of Water and Sanitation), supply forecast, and help requests that reach the water provider once enough neighbours vote.
- **Marketplace.** Farmers list stock. Buyers pay by card (Yoco) or cash. The server prices every order and holds the money until the buyer gives the delivery PIN.
- **Warehouse and stock.** Farmers see shop stock beside warehouse stock and the live room temperature. Cold-room alarms reach the farmer.
- **Dispatch and delivery.** The farm packs, prints the parcel label and scans it to send it out. Drivers see the job, the buyer and the farm follow the driver on a map, and the PIN closes the delivery.
- **Truck hire.** A farm asks for a bakkie or refrigerated truck, staff quote, the farm accepts.
- **Plans.** A farm switches plan by card and the new plan is on at once.
- **Works with weak signal.** Lists are saved on the phone. Stock changes, water votes and outbreak reports wait on the phone and send when signal returns.

## The backend

One Supabase project ("Nolifa Suite", Postgres + realtime + storage + Edge Functions).

| Part | Where | What it does |
|---|---|---|
| Database rules | `supabase/migrations/` | Every table has row-level security. Orders, money, approvals and plans are checked on the server. |
| Three doors | `drop_api`, `grow_api`, `delivery_api` | Each app talks to its own door and only sees what it needs. See `docs/APP_DOORS.md`. |
| Live updates | Supabase realtime | Approvals, orders, driver position and temperature reach the phone without a refresh. |
| Notices | `notifications` table | Approved, paid, packed, driver on the way, delivered, cold alarm. |
| Payments | Edge Functions `yoco-checkout`, `yoco-webhook` | Server-priced card payments for orders, memberships and plan switches. Only Yoco's signed message can mark something paid. |
| Staff | `backoffice/` (Flutter web, Firebase Hosting) | Approve farms and drivers, receive and store goods, post room temperatures, quote trucks, see drivers live, change plans. |
| Tests | `supabase/tests` (pgTAP), `packages/ubuntu_core/test_live`, `tools/e2e_cloud.py` | Database rules, the live backend, and a walk through approvals and payments in the cloud. |

## Technology

| Part | Built with |
|---|---|
| App | Flutter, Riverpod |
| Backend | Supabase |
| Plant diagnosis | Plant.id (called from the server) and an on-device TensorFlow Lite model |
| Weather | Open-Meteo |
| Dam levels | Department of Water and Sanitation State of Dams (KZN) |
| Maps | OpenStreetMap |
| Road incidents | TomTom Traffic |
| Payments | Yoco |
| Email | Resend |

API keys live in Supabase Edge Function secrets, never in the app or this repository.

## Run it

```bash
git clone https://github.com/MpumeleloM03/Nolifa-Grow.git
cd Nolifa-Grow
flutter pub get
flutter run --flavor nolifa -t lib/main.dart        # Nolifa Grow (everyone)
flutter run --flavor grow   -t lib/main_grow.dart   # farmers edition
```

Builds: `flutter build apk --release --flavor nolifa -t lib/main.dart`. The app connects to the shared Supabase project by default. To use your own, see `docs/SUPABASE_SETUP.md`.

## Security and privacy

- Row-level security on every table. Staff areas need a staff account.
- Outbreak locations are rounded to about 5 km. Each account can send at most 20 reports a day.
- Profiles are private, and users can delete their account in the app.
- Data goes to lenders or insurers only if the farmer switches it on (POPIA).

## Project layout

| Folder | What is in it |
|---|---|
| `lib/` | The app: role-based shell, diagnosis, outbreak map, water, selling, driver screens |
| `packages/ubuntu_core/` | Shared engine used by all four apps |
| `supabase/` | Migrations, Edge Functions, database tests |
| `backoffice/` | Staff web app |
| `tools/` | Account, seeding and test scripts |
| `docs/` | Setup, security and design notes |
