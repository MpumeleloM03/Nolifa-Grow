# Store readiness and accuracy plan

Honest status of what stands between the prototype and the App Store and Google Play, and how the accuracy of weather, roads and AI gets better.

## Delivery model (built)
- **Local delivery.** Farm within 25 road km of the buyer: one driver, farm to door, same day. Price R15 plus R2.50 a km after the first 3 km.
- **Hub delivery.** Farm further away: the order goes to the Nolifa hub nearest the buyer (Durban, Pietermaritzburg, Richards Bay, planned sites), and a last-mile driver brings it. R35 flat within 30 km of the hub, then R1 a km. Arrives in 1 to 2 days.
- **Farm delivers.** The farm's own fee.
- The app works out the distance from the farm and the buyer's address, picks the route, shows the price and what the buyer saves against one driver going the whole way (for example R35 instead of about R200 for an 85 km run). With no address it quotes R25 and says it is an estimate.
- **Not built yet:** the leg from farm to hub. Today the plan assumes the farm drops off at the hub or a shared collection run picks up; that run is not in the app and the hubs do not exist. Hub staff screens (receive, sort, release to a driver) are not built. This is the next piece of work and needs a real hub partner.

## What blocks a real store launch
| Item | Status | What is needed |
|---|---|---|
| Shared backend (accounts, orders, water, road alerts) | Written, switched off | Teammate connects Firebase. Run the rules tests (needs Java) |
| Real payments and escrow | Simulated | Licensed provider (FNB). Server decides release |
| Identity checks (farm, driver) | Simulated | KYC provider |
| Hubs and line-haul | Not built | Partner or own site, staff app |
| Push notifications | Local only | FCM and APNs keys |
| App Store and Play accounts | Not done | Apple Developer (USD 99 a year), Google Play (USD 25 once), signing keys |
| Privacy policy, data safety form, POPIA notice | Not written | Needed for both stores. Health, location and photo data are declared |
| Camera, location and notification permission texts | Set for iOS | Check Android manifests, review wording |
| Android build | Not tested this session | Build and run on a device |
| Release builds, app icons, screenshots | Icons exist | Release signing, store listing, screenshots |
| Crash reporting and analytics | None | Crashlytics (opt in) |
| Load and field testing | None | Pilot with real farms and drivers |
| Content review | Disease list not vet reviewed | A vet signs off the animal and crop advice |

## Making the weather, road and AI accurate
**Weather.** Already real (Open-Meteo, with observed weather for checking). Next: compare Open-Meteo against SA Weather Service stations for the region, show the measured miss on the Impact page, and add a local rain gauge entry so farmers can correct it.

**Roads.** Warnings are only as good as the number of drivers. Needed: the shared backend, driver reputation (confirmed reports raise trust, rejected ones lower it), automatic confirmation when several drivers pass a spot and see nothing, and a rate limit. Live GPS following is built but only checked on a simulator.

**Crop and animal AI.**
1. Collect 50 to 100 labelled photos per major KZN crop disease with an extension officer and score the scanner with `tools/scanner_eval.py`.
2. Use the farmer's Yes or No after each scan (Impact page) as a stream of labelled data, with consent, to find where the scanner is weak.
3. Have a state vet review every animal condition, sign and instruction. Until then the app says it is a guide.
4. Add a "talk to a vet or extension officer" button for any red result, because a model cannot replace one.
5. Publish the measured accuracy in the app with the sample size.

## For the judges
Everything in the app is labelled when it is simulated. The honest line is: the rules, the maths and the screens are real and tested; payments, identity, hubs and sharing between phones need the backend and partners.
