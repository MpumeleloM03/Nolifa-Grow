# Nolifa

Three Flutter apps for South African farms, households and drivers, built for the
FNB App of the Year theme *Climate resilience and essential services*. They share
one engine, `packages/ubuntu_core`.

| App | For | Where | Tabs |
|---|---|---|---|
| **Nolifa Grow** | Farmers | this folder | Home (crop scan, cattle symptoms), Orders, Alerts (outbreak map), Settings |
| **Nolifa Drop** | Customers | `~/ubuntu-drop` | Shop, Water, Alerts, plus a menu |
| **Nolifa Delivery** | Drivers | `~/nolifa-delivery` | Jobs, Earnings, Account |

A farmer registers a business, is verified and pays for a plan before selling.
Each farm chooses to deliver orders itself or use Nolifa Delivery. Payments sit in
escrow and release when the customer gives the 4-digit PIN.

All apps run on the phone with Supabase off. See `docs/SUPABASE_SETUP.md` to
connect the shared backend. Business model, security notes and judge answers are in `docs/`.

## Run

```bash
cd ~/nolifa-ios && flutter run          # Nolifa Grow
cd ~/ubuntu-drop && flutter run         # Nolifa Drop
cd ~/nolifa-delivery && flutter run     # Nolifa Delivery
```

## Test

```bash
flutter analyze && flutter test         # in each of the three apps
cd packages/ubuntu_core && flutter test # the shared engine
```

Demo mode (default) adds sample farms, neighbours and a water provider so every flow can
be shown on one phone. Turn it off in Trust and Safety to see real data only.
