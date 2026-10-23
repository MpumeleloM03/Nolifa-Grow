# Moving from Firebase to Supabase

Why: Firebase kept failing ("We could not reach the server"), the iOS 27 simulator cannot reach Firestore, and the rules were hard to test. Supabase gives a normal Postgres database with row level security (RLS), email sign-in, and realtime, and it can run on a laptop for testing.

Status key: [x] done, [ ] to do, [!] needs something from you.

## A. Project and tools
- [x] Cloud project `Nolifa Suite` created by you, migrations pushed and live tests passed against it.
- [x] Run Supabase on this computer with Docker to build and test everything first.
- [x] Push the migrations to the cloud project.
- [ ] Turn on email sign-in, set the site URL, and decide whether sign-up needs email confirmation.
- [ ] Create the first staff and certifier rows.

## B. Database (one migration per area, in `supabase/migrations`)
- [x] Profiles and roles: `profiles` (private wallet state, plan, checks), `water_prefs`, `staff`, `certifiers`, a `verified` flag only an admin can set.
- [x] Market: `products`, `orders`, `cases` with the same fields the app already writes.
- [x] Orders: the claim-a-job step as one safe database function, and a guard that only allows the same state changes as the old rules (money never changes, PIN tries, hub steps).
- [x] Water: `water_zones`, `water_incidents`, `water_votes` (one vote per person) with the vote as a function.
- [x] Roads: `road_hazards`.
- [x] Warehouse: `warehouse_lots`, `warehouse_readings`, `warehouse_certs`, `warehouse_picks`.
- [x] Grow: herd (`cattle`), `health_log`, `outbreaks`, chat messages.
- [x] Row level security on every table, translated from `firestore.rules`.
- [x] Database tests that replace the Firestore rules tests: 176 pgTAP checks plus 9 live tests.

## C. App code
- [x] Add `supabase_flutter`, remove `firebase_*`.
- [x] Core: Supabase versions of the market, water, road and warehouse repositories, and staff roles.
- [x] Sign-in and sign-up in Nolifa Grow, Nolifa Drop, Nolifa Delivery and the back office, with the same screens.
- [x] Grow-only pieces: herd, health log, outbreaks, chat.
- [x] One place for the project URL and anon key (build settings), with a fallback to on-phone mode.
- [x] Remove the Firebase files, plists and `google-services.json`. (Android json and rules removed. The iOS plist files stay in the Xcode project, unused, until someone edits the project file.)

## D. Testing
- [x] Repository tests against the local Supabase (two users, orders, claim race, votes).
- [x] All app test suites.
- [ ] Back office in a browser against the local stack (compiles and its unit tests pass; not clicked through yet).
- [x] Apps on the simulator against the local stack.

## E. Release
- [ ] Back office hosting (Supabase has no hosting: use Vercel or Netlify, or keep Firebase Hosting for the static site).
- [x] Update every document that says Firebase.
- [ ] Switch the Firebase project off once nothing uses it.
- [!] Real phones: test sign-up, orders and the warehouse.
