# Secure Software Development Lifecycle (SSDLC)

*Nolifa Drop x Nolifa Grow. Applies to the Flutter app, the Supabase backend and the Supabase security rules.*

This document says what we do at each stage, shows the evidence from the current build, and lists what is not done yet. Claims here are limited to things that exist in the repository.

---

## 1. Scope and what we protect

| Asset | Why it matters | Sensitivity |
|---|---|---|
| Money in escrow and payout records | Direct financial harm if altered | Critical |
| Identity and verification results (ID, selfie, payout account) | Fraud and privacy | Critical |
| Delivery PIN | Proves the buyer has the goods | High |
| Farm location, herd and disease records | Commercial harm and POPIA personal information | High |
| Outbreak cases | Trust in the alert system | High |
| Orders, listings, chat | Normal business data | Medium |

**Out of scope:** card data. We never store, process or see card numbers; payments run on FNB rails.

**Regulation:** POPIA for personal information. FICA and card rules are handled by the banking partner, which is also why verification is built on FNB identity checks.

## 2. Roles

- **Product owner:** sets security requirements and accepts risk.
- **Developers:** write code, write tests, review each other's changes.
- **Security lead (named in the team):** owns the threat model, the database tests and release sign-off.
- **Mediators and vets (production):** staff with special permissions, given by trusted admin tooling only.

## 3. Stage by stage

### 3.1 Requirements
Security requirements are written before features. The ones that shaped the build:

1. Nobody can change an order's money after it is created.
2. Each state change belongs to exactly one role (farmer packs, driver delivers, buyer confirms).
3. The delivery PIN must not be readable by the driver.
4. An outbreak report must not alert other farms until independently confirmed.
5. A dispute must freeze payment immediately and only a mediator can decide it.
6. Users see every fee and every payout rule before paying.
7. Private data (balances, plan, checks) is readable only by its owner.
8. Sharing farm data with FNB or businesses is optional and reversible.

### 3.2 Design
- **Architecture:** Flutter app, Riverpod state, a repository layer with two implementations (on-device storage, Supabase). The app never calls Supabase directly.
- **Trust boundaries:** the device is untrusted. Anything that matters is enforced by database rules or, in the next phase, by trusted backend code.
- **Data model:** private state in `marketProfiles/{uid}`, shared data in `marketProducts`, `marketOrders`, `marketCases`. Orders carry a participants list so each person can only query their own.
- **Threat model (STRIDE):**

| Threat | Example | Control | Evidence |
|---|---|---|---|
| **S**poofing | Fake driver or farm | FNB ID, selfie, payout account, vehicle checks before any job or listing | App flow, KYC gating tests |
| **S**poofing | Writing as another user | `request.auth.uid` must match the actor in every rule | Rules tests |
| **T**ampering | Edit fees or items after ordering | Money fields are immutable after create | Database tests, one per field |
| **T**ampering | Driver releases money early | Only buyer (or anyone after 2 hours) can release | Rules tests |
| **T**ampering | Two drivers take one job | Atomic claim, loser is rolled back | Claim tests (local and Supabase) |
| **T**ampering | Stale write overwrites newer order | Revision check on every write | Stale write test |
| **R**epudiation | "I never delivered" | GPS trail, pickup photo, PIN log, dispute timeline | Order model and UI |
| **I**nformation disclosure | Driver reads the PIN | Only a hash is stored in the shared order; the plain PIN stays on the buyer's device | Test checks the stored document has no PIN |
| **I**nformation disclosure | Reading another user's orders or profile | Participant-only reads, owner-only profiles | Rules tests |
| **D**enial of service | Spam listings or cases | Field limits in rules; rate limits and App Check in next phase | Partial |
| **E**levation of privilege | Buyer resolves their own dispute | Only a custom `mediator` claim can resolve | Rules tests |
| **E**levation of privilege | Reporter verifies own case | Only a custom `vet` claim, or independent neighbours | Rules tests |
| Abuse | False outbreak reports to hurt a supplier | Two-step confirmation; unverified reports never change a Radar rating | Radar test |
| Abuse | Radar harms the farmer it reports on | Reroute, not delist. Suppliers opt in to share status. Vet support and cover pointers | Radar screen and policy |

### 3.3 Implementation
- Secure coding rules: validate on the way in, never trust the client for money or permissions, no secrets in the repository, least privilege everywhere.
- The Supabase project config and keys are generated per environment (`flutterfire configure`) and are not committed with real production values.
- Dependencies are pinned by `pubspec.lock` and `package-lock.json`.
- Every change is reviewed by a second person before merging.
- Static analysis (`flutter analyze`) must report zero errors and zero warnings.

### 3.4 Verification
Current evidence:

| Check | What it proves | Result |
|---|---|---|
| App tests (`flutter test`) | Fee maths, escrow, PIN, disputes, report rules, persistence, two-phone sync, Radar | See section 6 |
| Row level security tests in a real Postgres (pgTAP) | 176 allow and deny checks across profiles, products, orders, drivers, hub, water, road warnings, warehouse and cases | All passing |
| Contract test | Replays every write the real app makes in a full lifecycle against the rules, so app and rules cannot drift | All passing |
| Static analysis | No errors or warnings | Clean |
| Build | iOS simulator build succeeds | Passing |

Run the database tests yourself (needs Docker):

```bash
supabase start
supabase test db
supabase/run_live_tests.sh   # signs in real users and replays what the apps write
```

Planned: dependency vulnerability scanning in CI, SAST on the Flutter code, a third-party penetration test before public launch, and a dynamic test of the production Supabase project.

### 3.5 Release
- Release only from a green build: zero analyzer issues, all tests passing.
- Separate Supabase projects for development, staging and production.
- Migrations are deployed from the repository (`supabase db push`), never edited in the dashboard.
- Turn on CAPTCHA and email confirmation for sign-up, and rate limits, in the Supabase dashboard.
- Staged rollout: internal, a small farmer group, then wider.

### 3.6 Operations
- Monitor failed permissions, spikes in disputes, unusual payout patterns and sign-in abuse.
- Incident response: contain (disable the affected feature or account), assess, notify users and the regulator when personal information is affected (POPIA), fix, then review.
- Backups and point-in-time recovery for Supabase.
- A published contact for reporting vulnerabilities.

### 3.7 Maintenance
- Monthly dependency updates, and the same day for critical security fixes.
- Re-run the threat model whenever a feature touches money, identity or sharing.
- Every incident adds a test so it cannot recur.

## 4. Controls mapped to code

| Control | Where |
|---|---|
| Money is immutable after creation | `firestore.rules`, `marketOrders` update rule |
| Role-based state transitions | `firestore.rules`, `marketOrders` |
| PIN stored as hash only | `lib/market/market_models.dart` (`hashPin`), `lib/market/market_codec.dart` |
| Atomic job claim | `lib/market/firestore_market_repository.dart` (`claimJob`) |
| Stale write protection | `lib/market/firestore_market_repository.dart` (`putOrder`) |
| Escrow window and release | `lib/market/market_store.dart` (`_observe`, `_release`) |
| Dispute freeze and settlement | `lib/market/market_store.dart` (`openDispute`, `resolveDispute`) |
| Verified-only Radar ratings | `lib/market/market_store.dart` (`riskOf`) |
| One payout per order per device | `lib/market/market_store.dart` (`_payouts`, `paid`) |
| Demo data never mixes with live data | `lib/market/market_store.dart` (`setDemoMode`, `seed` orders stay on device) |
| Only verified drivers add, confirm or reject road warnings | `lib/roads/road_store.dart` (`roadCanReportProvider`), `firestore.rules` (`roadHazards`) |
| Road warnings expire and cannot be back-dated or edited | `lib/roads/road_models.dart` (`activeAt`), `firestore.rules` (`recent`, update rule) |
| Impact numbers show sample size and interval, small samples are marked | `lib/impact/impact_models.dart` (`wilson`, `minSampleToClaim`) |
| Water saved counts only rain that did a watering's work, once per day | `lib/farm/farm_store.dart` (`holdOff`) |
| Valve links must be web addresses, one run per plot per day | `lib/farm/farm_setup_screen.dart`, `lib/farm/farm_store.dart` (`autopilotTick`) |
| Animal health records stay private to the owner | `firestore.rules` (`users/{uid}/healthLog`) |

## 5. Known gaps and the plan to close them

Being honest about these is part of the lifecycle.

| Gap | Risk | Plan |
|---|---|---|
| Order totals are computed on the phone | A modified app could write wrong totals | Trusted backend recomputes totals from product prices and rejects mismatches |
| Disputes are decided by a mediator claim, but no mediator console exists yet | Live disputes wait in review | Build the staff console; use the Supabase Admin SDK to grant the claim |
| Vet verification has no console yet | Live cases stop at neighbour confirmation | Vet portal and claim, same approach |
| Farm plan is stored in the user's own profile | A user could claim a cheaper commission | Plan written only by the billing backend |
| Balances and ledger are computed on the device | Only a display, but not authoritative | Backend writes the ledger when it settles money; app only reads it |
| Delivery PIN has 10 000 combinations | Brute force by a driver | Lock after 3 wrong tries, enforced server-side; App Check |
| Payments, ID checks and mediation are simulated | The prototype does not move real money | Integrate FNB payments and identity services in the pilot |
| No App Check or rate limiting yet | Automated abuse | Enable App Check and per-user write limits |
| Escrow auto-release is timed by whichever phone is open | A closed app may release late | Scheduled backend job releases at exactly 2 hours |
| A verified driver could report fake road hazards | Wrong warnings cause detours | Others can reject them, two rejections take one down, and reporting is rate limited once the backend is on. Add a reputation score |
| Irrigation autopilot only runs while the app is open | A locked phone does not water | Farm hub or scheduled backend function calls the valve |
| The irrigation AI cannot sense soil moisture | It assumes half the easy water is used until told | Optional soil sensors; until then the soil check buttons |

## 6. Test evidence, current build

- Shared package (`ubuntu_core`): 196 tests (fee and escrow rules, PIN, disputes, outbreak reports, stock, persistence, farms and the one-farm basket, business gating, water forecast, the real dam feed against a saved DWS page, voting rules on both storage backends, road hazard lifetime, geometry, verified-only reporting and the shared backend, encryption, the demo flow, and the shop, farm, business, settings, water and road screens).
- Nolifa Grow: 212 tests (the four tabs, stock, orders received, farm self-delivery with the buyer PIN, crop health advisor, the irrigation AI against hand-worked water balances, farm setup, valve and autopilot, impact evidence maths, four-species livestock with health records and the herd map, proof-backed community, hexagon map, alarm, water provider, weather, notifications, settings).
- Nolifa Drop: 36 tests (sign-in with device accounts, onboarding, the three tabs, the menu, settings, the Water tab).
- Nolifa Delivery: 28 tests (sign-in, driver onboarding, jobs, earnings, account, and the job route map with road warnings ahead and the report sheet).
- Database rules: 176 pgTAP checks in a real Postgres, including water votes (one per person, only while a community is Low or Critical, no skipping stages) and the water provider's allowed steps, plus 9 live tests that sign in real people and replay what the apps write.
- Static analysis: no errors or warnings in any of the four projects.
- Supabase is switched off by default; see `docs/SUPABASE_SETUP.md`.

### Water module threats
| Threat | Control |
|---|---|
| Fake or repeated votes | One vote document per account per request, enforced by the database; voting opens only when a community is Low or Critical |
| One person hiding a real request behind a fake one | Requests chain: a new request needs the previous one resolved |
| Anyone pretending to be the water provider | Only accounts with the `utility` permission can publish readings or answer requests, and only along the allowed steps |
| A request on a recovered community | The threshold-crossing vote is refused unless the reservoir is still below 40% |
| Misleading forecasts | The forecast shows its confidence and its reason, and says it is a statistical forecast from readings |
