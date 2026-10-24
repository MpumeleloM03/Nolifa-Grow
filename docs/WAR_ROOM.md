# War room: what is weak, and does it answer the problem

Date: 24 Oct 2026. Read from the code, the database and the docs. Every finding below was checked, not guessed. "Verified" means I read the code or ran it.

## The problem statement, and the honest answer

FNB App of the Year, theme: **climate resilience and essential services.** Our own pitch: "a farm and its neighbours stay fed and watered when something goes wrong", through Protect (disease), Prepare (water) and Provide (food delivery).

**Does it address it? In story, yes. In proof, no.**

| Claim | What exists | Verdict |
|---|---|---|
| Protect: early warning of disease | Leaf scanner (on-phone model), outbreak map, vet video consults, herd care | Real features. **Accuracy of the leaf model has never been measured** (EVIDENCE_KIT admits it). One partner vet, in one province, and no vet is actually signed up yet. |
| Prepare: water warning | Real DWS dam levels (KZN only, weekly), real weather, forecast | Real data. **Dams, not taps.** The community-vote and provider flow has **no zones published in the cloud database**, so it cannot run in production today. |
| Provide: food when supply fails | Marketplace, hub, drivers, batches | Built. **One real seller (Fatboy), no real buyers, no real money.** Escrow is bookkeeping, not an FNB product. |
| It works when things go wrong | | **Weakest point.** In a flood, outage or load-shedding the apps need internet for orders, sign-in and maps. There is no offline order path, no SMS or USSD, no feature-phone path. A resilience app that fails when the network fails is the first thing a judge will say. |
| Measured impact | Impact screen (forecast checks, water saved) | Self-measured, no farmer pilot, no loss figures. |

## Critical (could lose money, trust, or the store listing)

1. **The delivery PIN can be cracked by the driver.** The PIN is `sha256(orderId:pin)`. The order id is in the same row the driver reads, and there are only 10 000 PINs. A driver can find the PIN offline in milliseconds, so the "3 tries then lock" rule means nothing and money can be released without the customer. *Fix:* keep the hash in a table drivers cannot read, check the PIN in a database function that counts tries, use a server secret.
2. **The server trusts the buyer's phone for all money.** Lines, prices, delivery fee and totals are written by the buyer's app and only frozen afterwards. A buyer can create an order at R1 or with a R0 delivery fee. No check against the real product price. Payouts, escrow and commission are all worked out on the phone. *Fix:* build the order in a database function from real product prices and the fee formula.
3. **A farmer can lower their own commission.** The commission check reads the plan from the farmer's own private state, which they can write. Setting plan to co-op gives 3 percent instead of 8. Verified in `commission_for`. *Fix:* plan from a table only staff write.
4. **Any account can be a driver.** Driver verification is a tap-through mock ("Verify your ID with FNB", "Selfie match") and the server does not check it. Any signed-up user can claim jobs. Every signed-in user can read open jobs, which include the customer's name and drop area. That is a POPIA problem.
5. **Every user can read every user's email.** The `users` table is readable by all signed-in users and holds emails. Verified. *Fix:* split public profile from private.
6. **App Store blocker: no in-app account deletion.** Apple requires it (guideline 5.1.1(v)). Not built in any of the three apps. Also needs a deletion path for ID photos.

## High

7. **Fake-looking trust labels.** "Verify your ID with FNB", "checked against Home Affairs", "Selfie match" appear in the KYC steps. No FNB or Home Affairs integration exists. An FNB judge will notice. Rename to what is true or build the integration.
8. **Sign-up has no brakes.** Email confirmation is off, no CAPTCHA, no rate limits. Anyone signed in can add outbreak reports (not just verified people), chat, products and orders, so a bot can poison the outbreak heat map. Cheap to fix with a verified check and limits.
9. **Back office security.** Admin accounts have no second factor and can open ID photos. The admin password I set is weak and has been written in this chat, along with two access tokens. Rotate everything. Add MFA and an access log for ID photo views.
10. **Free public services used as if they were ours.** OpenStreetMap tiles, Nominatim, the OSRM demo server and Open-Meteo's free tier all forbid or limit heavy app use (tiles already returned errors in tests; the driver home looks up many addresses). One block and maps or weather go dark. Open-Meteo's free tier is non-commercial. Needs paid or self-hosted versions before launch.
11. **Video uploads on rural mobile data.** A 2 minute video is tens of MB, sent in one request with no compression, no resume, no background upload. This will fail often for the exact users who need it.
12. **Overclaims found in our own work:** the vet screen said "you will get a notification" and no push system exists (fixed in this commit, now says so). Docs still say the demo "nothing is faked silently" while shipped apps carry the mock KYC.
13. **Remote vet diagnosis has legal exposure.** South African veterinary rules expect a vet to know the patient and examine before prescribing. The remedies a vet writes remotely need a lawyer's view and a Veterinary Council check. We show a disclaimer, which is not enough on its own.
14. **A 24 month lock-in for R3 000 to R7 000 a month** needs a legal check under the Consumer Protection Act (cancellation rights, cooling off) before any money is taken.

## Medium

15. **Driver economics do not match "large amounts".** Local fee is R15 for 5 km then R2 per km, and drivers get 80 percent. A 10 km run pays the driver about R20. A batch of four drops is roughly R80 to R112 for 1.5 to 2 hours before fuel, about R50 to R60 an hour. Batching gives more per trip, not a living wage. Either raise fees or tell drivers the truth.
16. **Language.** Zulu covers 113 strings. The new screens (membership, vet, application, borehole, herd care, driver home) have no Zulu at all. No Xhosa, Sotho or Afrikaans. For farmers this is the main inclusion gap.
17. **Price versus users.** R3 000 a month is out of reach for most smallholders, the people the story is about. Who is the member? Commercial farms. Say so, or add a cheaper tier.
18. **Cold start.** A marketplace with one seller and no buyers has no resilience value yet. A pilot with 10 sellers and 100 households matters more than any new feature.
19. **Scale.** Apps stream whole tables (all outbreaks, all visible orders). Fine for hundreds, expensive and slow for tens of thousands.
20. **Not tested on real devices.** No Android run, no physical iPhone run, video and camera flows untested on hardware, no crash reporting, no analytics, no backup restore drill. The Android build is signed with the debug key and the Grow release key password is committed in plain text.
21. **Single hub, single region.** Durban hub only, KZN only. Fine for a pilot, not for "resilience across South Africa".

## What a hostile judge asks, and the current answer

- *"What happens when the network is down?"* Today: it stops. This is the biggest gap against the theme.
- *"Show me one farmer who is better off."* None yet.
- *"Is the money real?"* No. Escrow is app bookkeeping.
- *"How do I know your leaf AI works?"* We do not have a measured number.
- *"Why would a smallholder pay R3 000?"* They would not. Commercial farms might.
- *"Can a driver steal an order?"* Yes, by cracking the PIN (finding 1).

## Where it is genuinely strong

Honest labelling of real versus simulated, real data sources (DWS, weather, road hazards), a database that enforces order and vet rules itself (254 checks, 12 live tests), a coherent three-app story, vet video flow with quotas enforced on the server, and a farm application that staff actually review.

## Fix order (my recommendation)

1. PIN verification on the server (1) and server-built orders (2, 3). One focused day.
2. Driver verification enforced on the server and open-job data trimmed (4). Public and private profile split (5).
3. Account deletion in all three apps (6). Required to ship on iOS.
4. Honest KYC wording (7), verified-only outbreak reports and rate limits (8), MFA (9). Rotate every secret.
5. Offline order queue and SMS fallback, the real answer to "resilience" (the theme).
6. Paid or self-hosted maps and weather (10). Video compression and resumable upload (11).
7. Pilot with real farmers and buyers, and measure (leaf accuracy, orders, time saved).
