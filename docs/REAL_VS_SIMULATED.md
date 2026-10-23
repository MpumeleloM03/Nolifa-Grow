# What is real, and what is not

The shipped apps (Nolifa Grow, Nolifa Drop, Nolifa Delivery) and the back office show no demo content. This is the full list.

## Real today
| What | Source | How it uses where you are |
|---|---|---|
| Dam levels, this week and last week | Department of Water and Sanitation weekly State of Dams report (KwaZulu-Natal) | Puts the supply system nearest your GPS position first and marks it "Near you". Outside KwaZulu-Natal it says so |
| Water forecast (days to critical) | Smoothing of the weekly readings, corrected with real forecast rain from Open-Meteo | Same |
| Weather forecast and warnings (frost, heat, heavy rain, wind) | Open-Meteo, no key | Forecast for your exact position, named by the nearest suburb (OpenStreetMap Nominatim) |
| Evaporation for the irrigation AI | Open-Meteo ET0 | Your position |
| Checking forecasts against what happened | Open-Meteo observed weather | Your region |
| Road routes, distances and times | OSRM on OpenStreetMap | Driver position and the real addresses |
| Maps | OpenStreetMap tiles | |
| Place names and addresses | Nominatim | |
| Your position | The phone's GPS, asked once | |
| Accounts, orders, listings, wallet records | Firebase Auth and Firestore, shared between phones | |
| Road warnings | Reports from verified drivers, shared once drivers use it | Warnings within 15 km of you |
| Outbreak map and alerts | Real reports from farms, confirmed by neighbours | |
| Warehouse deposits, tags, bays, temperatures, cuts, certificates | Firestore, back office website | |
| The leaf scanner and animal checker | On-phone model and symptom data | |
| Fee, escrow, PIN and dispute rules, delivery route and price, irrigation maths | Code, tested | |

## Not real yet
| What | Why | What would make it real |
|---|---|---|
| Payments and escrow | No licensed provider connected | FNB or another provider holds the money; a server releases it |
| Identity, bank and farm verification | Simulated checks | KYC provider |
| Phone verification code | Demo code, no SMS | An SMS provider |
| Land inspection results | A person has to go | Inspector records the result |
| Tap-level water outages | No public feed exists | Municipal feeds and household reports |
| Dam data outside KwaZulu-Natal | Not built | Add other DWS provinces |
| Push notifications | Local only | FCM and APNs |
| Hub premises and staff | Software is built, the site is not | Nolifa rents or builds the warehouse |
| Room temperature probes | Staff type readings in | Sensors that write to `warehouseReadings` |
| Opening a valve | Needs the farmer's smart valve | A valve that takes a web link |

## Removed from the shipped apps
Demo farms and products, demo orders and wallet balances, the made-up alerts (load shedding, flood, armyworm, foot-and-mouth, frost), the demo outbreak map clusters, the demo community posts, the demo water communities and pretend water provider, sample road warnings, the demo warehouse stock, and the made-up forecast that used to appear with no signal. The code for them still exists for tests and presentations (it is switched on only by tests), and the Demo switch is hidden.

## Setting up people
- **Warehouse staff:** in the Firebase console, Firestore, create a document `staff/<their user id>` (any fields). They sign in to the back office at https://nolifa-backoffice.web.app with the account they signed up with. The back office shows their user ID if they have no access yet.
- **Certifiers:** create `certifiers/<their user id>` the same way. They record inspections on the Certificates page. A room cannot take goods until a certificate covers it.
- **Islilo Farming:** sign up in Nolifa Grow, set the farm name to Fatboy Butcheries and the suburb to uMhlanga, finish business setup and verification, then Orders, "Quick start: add the Fatboy Butcheries range".
