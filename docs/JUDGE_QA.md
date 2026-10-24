# Judge Q&A: straight answers

Short answers first, detail after. Where something is simulated in the prototype, we say so.

---

## Money

**Who pays what?**
The buyer pays items, delivery and a 3% service fee (minimum R2, maximum R15). The seller pays a commission only when a sale completes: 8% on Starter, 5% on Grow, 3% on Co-op. The driver is paid for the work: R12 a delivery plus R2.50 for every road kilometre, never under R24. The buyer's delivery fee pays towards it and Nolifa tops up the rest from the service fee and commission. The server records the amount when the PIN is accepted. Nolifa Drop keeps the service fee and commission after paying the driver. The split is shown before paying and on every receipt.

**Do we charge farms a monthly fee?**
Yes. Every selling farm pays a platform fee that includes support: Starter R49, Grow R99, Co-op R199 a month, on top of the commission. Grow pays for itself above about R1 700 of monthly sales, Co-op above about R5 000. A farm cannot sell until it has registered, been verified and chosen a plan. Supply Radar for businesses (Watch R1 500, Command R6 500, Enterprise custom) is the roadmap product, not in the three apps yet.

**Who pays the driver, and when?**
The driver is paid from the delivery fee when the order is released: either the moment the buyer confirms, or automatically 2 hours after delivery if the buyer says nothing and no dispute is open. Payment goes to an FNB account or Instant Money.

**Where is the money while the order is in progress?**
In escrow with the banking partner, not with the farmer or driver. In the prototype escrow is simulated; the production design assumes FNB holds the funds.

## Trust and security

**How do you verify outbreak reports?**
Three steps. The AI checks the photo and symptoms. At least two different neighbouring farms confirm. A vet or extension officer verifies. Only confirmed reports alert other farms, and only vet-verified reports carry the Vet verified badge. A single unconfirmed report never changes anyone's rating. One person can confirm a case only once, and reporters cannot confirm their own.

**What about false reports?**
They are private until confirmed, so they cannot trigger alerts or hurt a supplier. A reporter whose cases are repeatedly rejected loses reporting privileges. This is enforced by the same rules that stop a reporter promoting their own case.

**How do you stop a fake driver or fake farm?**
No job and no listing without verification: ID checked with FNB and Home Affairs, selfie match, payout account, and for drivers a vehicle and safety briefing. Ratings follow every account.

**What stops a driver marking an order delivered when it was not?**
Delivery completes only when the buyer's 4-digit PIN is entered. The PIN is never in the shared order, only its hash, so a driver cannot read it. There is also a pickup photo and a GPS trail. Even after delivery the buyer has 2 hours to dispute before anyone is paid.

**What if delivery goes wrong? What is the dispute path?**
The buyer taps Report a problem. Payment freezes immediately. A mediator reviews the GPS trail, pickup photo, PIN log and evidence, and decides within 48 hours. Outcomes: order never arrived, full refund. Damaged or wrong items, 50% of items refunded. Late, delivery fee refunded. Driver conduct, delivery fee refunded and the driver is reviewed. A second review can be requested, then escalation to FNB customer care. In the prototype the mediator step is simulated in demo mode; in live mode cases wait for a person.

**Is the app actually secure, or just says so?**
We test it. The database rules run in a real Postgres database with 176 allow and deny checks (editing money, spoofing users, a driver releasing money, a buyer resolving their own dispute, a reporter verifying their own case, one vote per person, warehouse staff only). A second suite signs in several real people and replays what the apps write. The gaps we have not closed yet are listed openly in the SSDLC document, with a plan for each.

## Fairness and privacy

**Supply Radar tells a retailer a farm has disease. Isn't that harmful to the farmer?**
It could be, so it is built carefully. Only verified cases count. Farms join a business's network and agree to share their status. A risk rating causes a temporary reroute, not a delisting, and volume returns when the vet clears the farm. Farms in an outbreak get priority vet support and are pointed to FNB cover for lost income. Businesses see only district-level data for farms outside their network.

**What about personal data?**
POPIA applies. Records are encrypted and never sold. Sharing sales history with FNB for credit or insurance is optional with a switch in the app, and off means no credit offers.

## Business

**How is this different from Plantix, Mr D or a farm marketplace?**
Each of them solves one problem. We connect three: an outbreak early-warning system, a delivery marketplace that works during disruptions, and a business risk product. The outbreak data makes the marketplace safer and the Radar valuable, and the payments rails make strangers willing to trade. The more verified cases we collect, the better the forecasts, which a new competitor cannot copy quickly.

**Why would FNB want this?**
It brings unbanked farmers, spaza owners and drivers onto FNB rails, creates payment volume, builds a transaction history that supports farm credit and insurance (with consent), and gives FNB a visible role in community resilience.

**What is the crop health AI, and is it a trained model?**
Two parts. The leaf scanner is a trained on-phone model. The harvest tracker is an agronomic estimate, not a neural network, and the app says so: it starts from the crop calendar, then slows or speeds the clock using the farmer's own scans and watering, and widens its range when it has little evidence. It gives the growth stage, days to harvest with a range, a confidence level and advice. It also checks a sprinkler plan against what the crop needs.

**How do you stop community posts being just talk?**
A post cannot be sent without proof. Crop posts carry an on-phone AI scan, livestock posts carry a symptom check and a photo of the animal, and water posts carry a photo of the tank or tap. Neighbours confirm with "I see this too". The AI is a guide, not a diagnosis, and the app says that.

**Why three apps?**
Each person gets only what they need. Nolifa Grow is a crop and cattle health app first, with selling as one tab. Nolifa Drop is for customers: shop, water, alerts. Nolifa Delivery is for drivers. They share one engine (fees, escrow, PINs, disputes, water), so a farmer, a customer and a driver see the same order.

**How does a farmer start selling?**
In Nolifa Grow they register the business (individual, co-op or company), complete verification (ID, payout account, farm location) and pick a plan. Only then can they add stock, and only then does their farm appear on Nolifa Drop. They also choose whether the farm delivers orders itself, with its own fee, or uses Nolifa Delivery.

**Does a surveyor inspect every farm before it sells? Is that fair to rural farmers?**
Every farm is inspected, but not before it can earn anything. A strict surveyor-first rule would shut out remote smallholders: long waits, travel costs, a lost season. So a farm that is registered, verified, on a plan and has shown its land and crops with geo-tagged photos can sell fresh whole produce straight away, up to R2 000 and for 45 days. Eggs, milk and processed goods wait for the inspection. There are three inspection routes (surveyor, extension officer, co-op inspection day) so a remote farm is never stranded. Details in `docs/INSPECTION.md`.

**What if the farm delivers itself?**
The order still goes through escrow. The farmer packs it, marks it out for delivery, and enters the customer's 4-digit PIN at the door. The farm keeps the delivery fee it set, and Nolifa takes no driver cut. Customers see "Farm delivers" on the farm's card before they order.

**What is real in the prototype, and what is simulated?**
Real: the app, offline storage, the fee and escrow rules, PIN delivery, disputes logic, outbreak verification logic, the backend layer and the security rules with their tests. Simulated: FNB payments and identity checks, vet and mediator decisions, neighbour drivers in demo mode, and the weather and forecast feed. A switch in the app turns demo mode off to show only real data.

**What happens next?**
Phase 1: connect Supabase, add the trusted backend for totals and settlement, mediator and vet consoles. Phase 2: pilot with FNB payments and identity in one district. Phase 3: scale to more districts and bring the Supply Radar to the first business customers.

## Water

**Where does the water data come from?**
The water provider publishes reservoir readings for each community, through the provider desk or an integration with its own sensors. In the prototype the readings are simulated and labelled "Provider feed (demo)". We do not scrape public pages or invent readings.

**Is the radar really AI?**
It is a statistical forecast, and the app says so. It applies double exponential smoothing to the reservoir readings, which tracks both the level and how fast it is falling, then projects it forward. It reports days until Low (40%), Critical (20%) and empty, how confident it is, and a plain sentence on why. It is explainable and works offline. Known demand (a heatwave) or rain can bend the trend. Learned models come later, once we have enough real readings to validate them.

**How do you stop fake votes?**
Each account counts once per incident, enforced by the database, not just the app. Voting only opens when a community is Low or Critical, so a healthy community cannot trigger anything. Votes are counts, so a few accounts cannot send trucks on their own: the threshold is set per community by the provider. The gaps we have not closed yet: in production, accounts will need a verified phone number or ID, and voting will be limited to people located inside the community. The provider also sees how fast votes arrive, which makes brigading visible.

**Why would a water provider send trucks because people voted?**
Today a request is one phone call among thousands. Votes give the provider one clear, counted demand signal per community, with a forecast of when the reservoir will run low, so trucks can be planned before the taps dry. Every stage is public, so a request that is ignored is visible. The provider decides: it acknowledges, chooses how many trucks and the ETA, and resolves. The votes recommend; they do not command.

**What if no trucks are available?**
The provider acknowledges with a note, and the community sees that. Meanwhile the app's planner tells people exactly how many 25 L bottles close the gap, and neighbour delivery brings them.

**Is the water safe?**
We do not test or certify water. Tankers and quality are the provider's responsibility. We only carry the request and the status.

**Do farmers get this too?**
Yes. Nolifa Grow has the same radar plus a livestock figure: the herd register is turned into litres a day, so a farmer sees how many days the tank covers.

## Climate and impact

**How does it help climate resilience?**
Disruption alerts turn into one-tap orders for water and food. Short supply chains cut spoilage. Rescue pricing sells produce at risk of frost or glut instead of wasting it. Early outbreak warnings reduce crop and herd losses. Farms get a plan when weather or disease hits.

## The tough questions

**Isn't this too many products for one pitch?**
It is one proposition: community resilience. Protect (farm health and outbreak warning), Prepare (water forecast and asking together), Provide (food that keeps moving). The three apps are that proposition for three people. See `docs/PITCH.md`.

**The water radar needs a provider. What if none takes part?**
The app says where the numbers come from, how fresh they are, who responds and what happens when nobody does ("Where this comes from" on the Water page). Votes stay public, the planner covers the gap with bottles, and farm suppliers can answer. The demo shows the complete loop with labelled test data and the provider's side of it. The provider's reply is the one part that needs their participation.

**Paid plans against a mission of free knowledge for farmers?**
The tools that protect a farm are free for everyone: scanning, symptom checks, the water radar, alerts and the community. Only selling has a plan, from R49, and the app lists what is free and what is paid. The prices are hypotheses we test with farmers first (`docs/VALIDATION_PLAN.md`).

**Do the apps really work offline?**
Some of it. The leaf scanner, symptom checker, herd register, crop tracker and your saved data work with no signal. Orders, payments, fresh water readings, the community, maps and navigation need a connection. Deliveries, water trucks, outbreak confirmation and inspections need another person. The app has a page for this (Trust and Safety, What works offline). In the prototype the apps store data on the phone, so two phones do not see each other until the shared backend is switched on.

**Payments, verification and provider integrations are big responsibilities. What is real?**
Real: the fee and escrow rules, the PIN, disputes logic, forecasts, AI scans and storage on the phone. Simulated: FNB payments, identity checks, inspection results, provider readings and replies. Each of these is labelled in the app (checkout, wallet, verification, inspection, water) and listed under Trust and Safety. The plan to make them real is in `docs/VALIDATION_PLAN.md`.

**Can someone guess the delivery PIN, or fake votes and outbreaks?**
No. Three wrong PIN tries lock the order, open a dispute and freeze the money. Only verified people can vote on water or confirm an outbreak, so extra accounts count for nothing. In production a licensed provider holds the money and a server, not the phone, decides when it is released. Personal data on the phone is encrypted. See `docs/SECURITY.md` and the security slide.

## Real data and measured results

**Is the water data real?**
Part of it. The dam levels come from the Department of Water and Sanitation's weekly State of Dams report for KwaZulu-Natal: Midmar, Albert Falls, Nagle, Inanda and the others, with this week and last week. The supply systems for Durban and Pietermaritzburg are worked out from those dams. The forecast is a trend with a rain correction from Open-Meteo, and its confidence is capped because we only have two weekly points. What is not real: tap-level outages, municipal restrictions and household votes (until the shared backend is on). The road map to close those gaps is in `docs/WATER_ROADMAP.md`.

**How do you know the app is accurate?**
It measures itself. After each scan the farmer says Yes, No or Not sure. The Impact page shows the share that agreed, how many answers it rests on, a 95% range (Wilson interval), and whether the scanner's confidence is actually informative. Forecasts are saved the day before and compared with Open-Meteo's observed rain and temperature. Harvest dates are compared with what the app predicted when the crop was added. Under 30 cases it says "too few to claim". A farmer's verdict is an opinion, not a lab test, and the page says so. A labelled sample set exists for demos and is never saved.

**Can the app prove it saves water?**
Only in a narrow way, and it says which. When rain does the work of a watering and the farmer confirms they held off, the litres a daily schedule would have pumped for that day are counted. Holding water back that will be needed next week is a delay, so it counts for nothing. The page shows the litres and the number of runs.

**Does the irrigation AI turn on my sprinklers?**
Not unless you link a smart valve. It plans from the FAO-56 water balance (crop factor times reference evaporation, minus effective rain, against what the soil can hold and the crop can use), tells you when, how much and for how long, and shows why in plain words. With a valve that takes a web link it can open the valve in the morning while the app is open. Running with the phone locked needs a small farm hub or a server, and that is on the road map. It is a rule-based model, not a neural network, and it shows how sure it is. A quick feel of the soil (dry, fine, wet) sharpens it.

**Can drivers warn each other about bad roads?**
Yes, like Waze. On a job the driver sees the route to the farm and then the customer. One tap reports a pothole, flood, crash, roadworks, roadblock, lights out, blocked road or animals. Warnings ahead on the route show with the distance, and close to one the app asks "still there?". A warning fades by itself unless another driver confirms it and comes down when drivers say it is gone. Only verified drivers can report. Reports are shared once the backend is on; today they stay on the phone and the samples are marked.

**Farmers keep goats, sheep and horses too. What does the app do for them?**
The register holds cattle, goats, sheep and horses, each with its own classes and breeds. The symptom checker offers only the signs and diseases that fit the species (colic and African horse sickness for horses, pulpy kidney and barber's pole worm for goats, flystrike and sheep scab for sheep). Controlled diseases are flagged first and the advice never gives a dose. Each animal has a health record, a location pin and a state on the herd map, and a group of sick animals close together is flagged.

**A driver should not drive 70 km to a farm and 90 km back. How does delivery work?**
Like a big online shop. If the farm is within 25 road km of the buyer, one driver collects and delivers the same day. Further away, the order goes through the Nolifa hub nearest the buyer and a local driver brings the last stretch, usually in 1 to 2 days. The app works out the distance from the farm and the buyer's address, chooses the route, and shows the price and the saving (about R35 instead of about R175 for an 85 km run). What is not built yet: the hubs themselves and the farm to hub leg. They need a partner and are listed in `docs/STORE_READINESS.md`.

**What is the warehouse?**
A Nolifa-owned cold store. Farms deposit supply, staff check each delivery in (weight and temperature), and goods that arrive outside the room's band are turned away. Accepted goods get a tag and a bay, sit in a chilled, frozen, cool or dry room, and every movement is logged on the lot. Orders from far away are picked from the oldest stock first. The farm sees its own lots and their history. In the prototype the temperature sensors are simulated, and there is no printed tag or barcode scanner yet.

**Who is Fatboy Butcheries?**
A real butchery in uMhlanga owned by Islilo Farming. The demo catalogue uses ten of its products with the prices from its own online shop. Orders for them travel through the warehouse because uMhlanga is far from many buyers.
