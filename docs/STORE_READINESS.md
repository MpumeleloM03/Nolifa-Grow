# Store readiness and accuracy plan

Honest status of what stands between the prototype and the App Store and Google Play, and how the accuracy of weather, roads and AI gets better.

## Delivery model (built)
- **Local delivery.** Farm within 25 road km of the buyer: one driver, farm to door, same day. Price R15 for the first 5 km, then R2 a km.
- **Hub delivery.** Farm further away: the order goes to the Nolifa hub nearest the buyer (Durban, Pietermaritzburg, Richards Bay, planned sites), and a last-mile driver brings it. R35 flat within 30 km of the hub, then R1 a km. Arrives in 1 to 2 days.
- **Farm delivers.** The farm's own fee.
- The app works out the distance from the farm and the buyer's address, picks the route, shows the price and what the buyer saves against one driver going the whole way (for example R35 instead of about R175 for an 85 km run). With no address it quotes R25 and says it is an estimate.
- **Hub flow (built):** the order stays hidden from drivers until it has passed through the hub. The farm packs it, writes a 4-digit code on the packing slip and taps "I dropped it at the hub". Hub staff open the Hub desk (Nolifa Delivery, Jobs page), type the code to check it in, then release it. Only then does it become a last-mile job, collected at the hub. The customer sees each step on the tracking page. In the demo a pretend farm and hub move orders along after 8, 20 and 32 seconds unless someone acts first.
- **Not built yet:** the hubs themselves (sites, staff, a real place to store goods), the farm to hub collection run, a real hub staff onboarding flow (staff are added by hand to the `staff` table). The hub code is derived from the order number, so on the real backend the server must check it. The hub database tests pass.

## The Nolifa warehouse (built)
A warehouse owned by Nolifa where farms deposit supply, and where far-away orders are packed from.
- **Deposit.** A farm announces what it is bringing (product, kg, room, use-by date, arrival day) from Settings, Nolifa warehouse. It sees every deposit with its status.
- **Check-in.** Warehouse staff (Nolifa Delivery, Jobs, Hub desk, Warehouse) weigh the goods and take the temperature. Goods outside the room's band (chilled 0 to 4 C, frozen -25 to -15 C, cool room 8 to 12 C, dry store 10 to 25 C, with 1 degree of slack) are turned away with the reason. Accepted goods get a tag (`NLF-DBN-0001`), a bay (`C1-01`) and a history that logs every movement.
- **Stock by room.** Tagged lots are listed per room, soonest use-by first. Past use-by lots are written off. Goods expire first out first (FEFO).
- **Rooms.** Each room shows its temperature against its band. A reading out of range raises an alarm and holds that room's goods back from orders. In the demo the sensors are simulated and a "Door left open" button shows the alarm.
- **Orders.** If the whole basket is already in the warehouse, a hub order skips the farm drop-off. Staff pick from the oldest lots and release it to a last-mile driver, and the lot history shows the order.
- **The farm sees it.** Its own lots, tags, remaining quantity, temperature at check-in and history.
- **Back office website (built):** https://nolifa-backoffice.web.app. Warehouse staff sign in and get: an overview with warnings, receiving (check in, then print the tag), scan (a barcode scanner types the tag; shows the lot and its history), stock (every lot, print, move, remove with a reason), pick and cut (each paid order: cut each line from the oldest stock, weigh it, print the dispatch label, release to a driver), rooms (temperatures) and certificates.
- **Tags:** 100 x 60 mm labels with a Code 128 barcode of the tag, product, farm, room, bay, quantity, check-in date and temperature, and use-by date. They print from the browser to any label printer.
- **Certification (built):** a certifier (added by an admin) records an inspection of the rooms. Each room needs six checks passed, and a certificate lasts 12 months. A room cannot take goods without a valid certificate. No abattoir paperwork is asked for, because farms set their own prices and the certifier covers the warehouse.
- **Not built:** real temperature probes (readings are typed in), camera scanning in the browser (use a barcode scanner), bay maps, stock-take reports, and a farmer view in the browser.

## Islilo Farming and Fatboy Butcheries
- The catalogue now has Fatboy Butcheries (uMhlanga), owned by Islilo Farming, with ten products taken from its own online shop at their shop prices (mince, fillet, stew, T-bone, brisket, sausage and chicken cuts). In the demo it has stock in the warehouse, so an order shows the tagged-stock flow.
- A real Islilo account: sign up in Nolifa Grow, set the farm name to Fatboy Butcheries and the suburb to uMhlanga, finish business, verification and plan, and (for meat) the inspection. Then Orders, "Quick start: add the Fatboy Butcheries range" lists the ten products as its own.
- Real shared accounts need the Supabase backend, which is off. Accounts made now live only on the phone they are created on. Creating production users in the shared Supabase project is a decision for the backend owner, so none were created.

## What blocks a real store launch
| Item | Status | What is needed |
|---|---|---|
| Shared backend (accounts, orders, water, road alerts, warehouse) | Built and tested against a local Supabase: 176 database tests and 9 live tests pass. Needs the cloud project created and the migrations pushed (see SUPABASE_SETUP.md) | Check on real phones. Sign-up on the iOS 27 simulator works against the local database |
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
