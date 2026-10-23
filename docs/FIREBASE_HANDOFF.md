# Firebase handoff

**Update:** Firebase is now ON by default in all three apps (`--dart-define=USE_FIREBASE=false` turns it off). The Nolifa Delivery app and a web app for the back office are registered in project `nolifa-grow-f3df9`, the security rules are deployed, and the back office is hosted at https://nolifa-backoffice.web.app. Staff and certifiers are people added by hand to the `staff` and `certifiers` collections (see `REAL_VS_SIMULATED.md`). The text below is the older handoff and still describes the pieces.

All three apps now run **entirely on the phone**. Firebase is switched off by default so nothing depends on a backend. Everything below is already built and tested, waiting for whoever connects the shared backend.

## What the apps do without Firebase
- Accounts, orders, stock, wallet, water votes and the demo are saved on the device.
- **The apps do not share data in this mode.** Each app has its own storage, so stock a farmer adds in Nolifa Grow does not appear in Nolifa Drop, and a driver in Nolifa Delivery does not see Nolifa Drop orders. That is the job the shared backend does.
- Demo mode (the default) fills each app with sample farms, simulated neighbours, five water communities and a pretend water provider, so every flow can be shown on one phone.

## Turning Firebase on
All apps check one switch, `--dart-define=USE_FIREBASE=true`:

```bash
cd ~/nolifa-ios && flutter run --dart-define=USE_FIREBASE=true
cd ~/ubuntu-drop && flutter run --dart-define=USE_FIREBASE=true
cd ~/nolifa-delivery && flutter run --dart-define=USE_FIREBASE=true
```

Without it, `FirebaseBoot.init()` returns immediately (see `lib/services/firebase_boot.dart` in each app). To use the local emulators instead of the real project, add `--dart-define=FIREBASE_EMULATOR=true`.

## What is already there
| Piece | Where |
|---|---|
| Firestore project `nolifa-grow-f3df9` (database in `nam5`) | Firebase console |
| Nolifa Grow (`com.nolifagrow.nolifaGrow`) and Nolifa Drop (`com.ubuntudrop.ubuntuDrop`) registered. **Nolifa Delivery (`com.nolifa.delivery`) still needs registering**; its `firebase_options.dart` and plists are copied from Drop and must be replaced | `lib/firebase_options.dart`, `GoogleService-Info.plist`, `google-services.json` in each app |
| Shared storage layer with a Firestore version and an on-device version | `packages/ubuntu_core/lib/market/*repository*.dart`, `lib/water/*repository*.dart` |
| Security rules for orders, products, outbreak cases, water zones, votes and the provider's actions | `firestore.rules` |
| Rules tests in the real emulator, plus contract tests replaying what the apps write | `firebase/rules-tests/` (see `FIREBASE_SETUP.md`) |
| Sign-in service for Nolifa Drop and Nolifa Delivery (Firebase or device accounts) | `ubuntu-drop/lib/auth/`, `nolifa-delivery/lib/auth/` |

Deploy rules with: `firebase deploy --only firestore:rules --project nolifa-grow-f3df9`

## New things the backend needs to take over
| Feature | Today (on the phone) | Backend job |
|---|---|---|
| Land and crop inspection | Business profile holds the status; a demo button passes it | An inspection service writes the result and the visit date. Only it may set `inspection` to passed or failed. Rules for the farm's own profile must stop a farm setting its own result |
| Community posts with proof | `communityStoreProvider`, device only, demo posts for neighbours | A `communityPosts` collection plus Storage for the photos. Posts need a photo URL and the AI summary. Confirmations once per person |
| Municipality updates | Read from the water incidents (provider answers) | Already shared once the water collections are on |
| Water suppliers (farms helping) | Local supplier profile; answering a request uses the provider desk | A `waterSuppliers` collection, approved by the provider, and a rule letting approved suppliers dispatch |
| Delivery proof photo | The driver app opens the camera and requires a photo; it is not kept | Upload to Storage and store the URL on the order (`deliveryProof`) with a matching rule |
| Notifications | Local notification on app open ("Welcome back") | Push (FCM) for orders, water and outbreaks, honouring the Settings toggles |
| Crop plots, sprinkler plans | Saved on the phone per account | Optional sync under the user's own document |
| Road hazard warnings | `LocalRoadRepository` on the phone, labelled samples | `FirestoreRoadRepository` and the `roadHazards` rules are written (verified drivers only). Run `npm test` for `roads.rules.test.js`. Consider TTL deletion of old documents and geohash queries once there are many |
| Hub orders | Pretend farm and hub in demo; real steps work between phones on the shared backend | `hubStage` rules and `roads`-style tests are in `firestore.rules` and `firebase/rules-tests/hub.rules.test.js` (unrun, no Java). Issue the `hub` custom claim to staff. Hub staff need a query for orders with `route == hub` (the app only lists orders the user takes part in). The server must verify the hub code, because it is derived from the order number |
| Warehouse | Lots and temperature readings on the phone; pretend sensors in demo | `FirestoreWarehouseRepository`, the `warehouseLots` and `warehouseReadings` rules, and `firebase/rules-tests/warehouse.rules.test.js` (unrun, no Java). Staff need the `hub` claim. Real temperature probes should write `warehouseReadings` from a trusted source. A web back office can read the same collections. Picking from stock is done by staff phones, so two staff picking at once need a transaction |
| Real dam levels | Each phone reads the DWS weekly page and Open-Meteo | A scheduled function (Mondays) fetches DWS with the same parser, writes `waterZones/{id}` with `source: DWS`, and phones stop scraping. See `docs/WATER_ROADMAP.md` |
| Animal health records | Sealed on the phone | `users/{uid}/healthLog/{id}` rule is in place; the app already writes there when Firebase is on |
| Impact evidence | Sealed on the phone per account | Optional sync of the ledger under the user's own document, plus an anonymised aggregate for funders |
| Farm setup and irrigation | Sealed on the phone per account | Optional sync. For background running, a farm hub or a scheduled function that calls the valve |

## Security items for the backend
| Item | Backend job |
|---|---|
| Server-side escrow | A licensed provider holds funds. A server function checks the PIN hash, counts tries, and is the only writer of `released`, `delivered` and `deliveredAt`. Then remove those client writes from the rules |
| PIN attempts | Rules for `pinAttempts` and the `pinLocked` dispute are in `firestore.rules`. Run `npm test` in `firebase/rules-tests` (needs Java) |
| Verified voices | Issue a `verified` custom claim after farm verification or a phone code. One verified number per account. Votes and case confirmations already require it |
| Data at rest | The apps encrypt local data. Add server-side encryption, a retention policy, and export and delete for POPIA |

## Known problem on the iOS 27 simulator
With Firebase on, the iOS simulator connects to Auth fine, but Firestore's streaming connection fails with `Unknown: An internal error has occurred`, then "offline". The same machine reaches Firestore over HTTP/2 from the command line, and the emulator (plain, local) works. The gRPC library in the app has no root-certificate file in its bundle, which is the most likely cause. Things to try, in order:
1. Run on a real iPhone, or an older simulator runtime.
2. Update the Firebase plugins (`cloud_firestore`, `firebase_core`, `firebase_auth`); this pulls a newer Firebase iOS SDK.
3. For the simulator only, point gRPC at the Mac's certificates: `setenv("GRPC_DEFAULT_SSL_ROOTS_FILE_PATH", "/etc/ssl/cert.pem", 1)` in `AppDelegate`, before Firebase starts (not yet tested).

## Still to do on the backend (see SSDLC, section 5)
- A trusted backend (Cloud Functions) that recomputes order totals, settles escrow and ledgers, and releases at exactly 2 hours.
- Mediator and vet consoles, and the custom claims `mediator`, `vet` and `utility` (the water provider).
- Water provider data: reservoir readings arrive through the provider desk or an integration with the provider's sensors.
- App Check, per-user rate limits, verified phone or ID for voting, and location checks for water votes.
- Push notifications for water and order alerts.
