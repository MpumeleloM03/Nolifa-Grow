# Nolifa Drop x Nolifa Grow: Lean Canvas

*FNB App of the Year, theme: Climate resilience and essential services.*

Numbers marked **[source]** need a citation from the research teammate before we say them out loud. Everything else is a product decision or a calculation from the app's own fee rules.

---

## 1. Problem

1. **Farmers hear about outbreaks too late.** Disease spreads between farms before anyone official confirms it. Information lives in WhatsApp groups and rumour, so one farm's loss becomes a district's loss.
2. **Households and spazas cannot rely on water and food during disruptions.** Water cuts, load shedding and flooded roads hit townships hardest, and fresh food from nearby farms rarely reaches them.
3. **Businesses buy blind.** A retailer finds out a supplier's herd is infected when the product stops arriving, not when risk first appeared.

**Existing alternatives**
- Farmers: WhatsApp groups, extension officers (stretched thin), Plantix (crop photos only).
- Households: Mr D, Uber Eats, supermarket delivery (not built for disruption, not for farm produce, not township-ready).
- Businesses: supplier audits and after-the-fact recalls.

## 2. Customer segments

| Segment | Who | Why they care |
|---|---|---|
| Smallholder farmers (start: KZN) | Crops and livestock | Early warning, vet help, a way to sell and get paid |
| Households and spazas | Disruption-prone areas, e.g. Umlazi | Water and fresh food when taps and shops fail |
| Neighbour drivers | Unemployed youth with a bike, car or bakkie | Local income, trusted payouts |
| Businesses | Retailers, processors, restaurants | Early supply-risk warning, backup suppliers |
| Water providers and municipalities | Utilities that run reservoirs and tankers | A clear, evidence-based demand signal, forecast of shortages, fewer duplicate calls |
| Partners | FNB, insurers | Verified data, new customers, resilience |

**Early adopters:** Greater Durban smallholders who already use Nolifa Grow, and the spazas and households around them.

## 3. Unique value proposition

> **Farmers get warned, get help, get paid. Households get fresh food when it matters. Businesses see supply risk before it hits the shelf.**

Short version: *an early-warning system for farms, joined to a trusted neighbour delivery network, with FNB-grade payments underneath.*

## 4. Solution

- **Nolifa Grow** (the farmer's app). Four tabs: **Home** (AI crop scanner and cattle symptom checker first, herd register, recent scans), **Orders** (what the farm has made, how many orders to send out, order and payout notifications, stock, and the business setup for selling on Nolifa Drop), **Alerts** (the outbreak map, what is happening in the farmer's area, reporting and details) and **Settings**. The scanner and herd tools work offline. isiZulu available.
- **Nolifa Drop** (the customer app). Three tabs: **Shop** (laid out like a food app: farms with their name in bold and their offerings, a cart, search), **Water** (forecast, alerts, community vote) and **Alerts**. A menu on Shop holds orders, wallet, settings, trust and safety and help.
- **Nolifa Delivery** (the driver app, separate so the other two stay light). Jobs, earnings and verification. Farms choose per store whether they deliver themselves or use Nolifa Delivery.
- **Selling is gated, but not by a surveyor first.** A farm registers, passes verification, pays for a plan and shows its land with geo-tagged photos, then sells fresh produce with limits while an inspection (surveyor, extension officer or co-op day) is arranged. See `INSPECTION.md`. That is also how Nolifa earns from platform use and support.
- **Water radar** (in both apps): the water provider's reservoir readings become a 7-day forecast and alerts. People check their community's supply, plan for the worst case, and add their voice. When enough different people ask, the request reaches the provider's desk and the provider sends trucks. Every stage is visible to the community.
- **Verified outbreak reports:** AI check, then neighbour confirmation, then vet verification. Only verified cases alert other farms.
- **Supply Risk Radar** (prototype kept in the shared code, not in the three apps' tabs yet): verified risk and a 7-day forecast per supplier, backup suppliers, temporary reroute. It becomes the business product once real supplier data exists.
- **Trust and Safety centre:** every fee, payout rule, check and dispute step is shown in the app.

## 5. Channels

1. **FNB:** in-app placement, eBucks rewards, Instant Money for people without bank accounts.
2. **Vets and extension officers:** they verify cases and bring farmers on.
3. **Co-ops and farmer associations:** one introduction reaches many farms.
4. **Spaza networks and community champions** in target townships.
5. **SMS and WhatsApp alerts** for low-data users.
6. **Direct sales** to retail and food-processing buyers for Radar.

## 6. Revenue streams

| Stream | Rule | Who pays |
|---|---|---|
| Buyer service fee | 3% of items, minimum R2, maximum R15 | Buyer |
| Seller commission | 8% (Starter), 5% (Grow), 3% (Co-op), only on completed sales | Farmer or spaza |
| Delivery margin | 20% of the delivery fee; driver keeps 80% | Buyer, via delivery fee |
| Farm plans (platform fee, includes support; required to sell) | Starter R49, Grow R99, Co-op R199 per month | Farmer |
| Supply Radar (roadmap) | Watch R1 500, Command R6 500, Enterprise custom, per month | Business |
| Water Radar for providers | Per-community subscription for the forecast, the request queue and the dispatch tools. Price to be set with a pilot municipality | Water provider |
| Partner referrals | Farm credit and cover referrals to FNB and insurers, **only with the farmer's consent** | Partner |

**Worked example from the app:** a R129.03 order splits R92.92 to the farm, R20.00 to the driver and R16.11 to Nolifa Drop. That is about 12.5% of the basket.

**Illustrative month (assumptions, not forecasts):** 2 000 orders at R130 average is about R32 000 platform take. 200 farms on Grow is R19 800. Ten Command subscribers is R65 000. Radar is the highest-margin line and needs few customers.

## 7. Cost structure

- Cloud (Supabase, SMS, maps).
- Payment and escrow costs with the banking partner.
- Driver payouts (80% of delivery fees, passed through).
- Vet and extension network for verification.
- Dispute mediators and support.
- Security, privacy and compliance (POPIA, penetration tests, audits).
- Farmer and driver onboarding and marketing.

## 8. Key metrics

**Trust:** time from report to verification, dispute rate, share of disputes resolved inside 48 hours, false-report rate.
**Marketplace:** orders per week, delivery success rate, repeat purchase rate, average payout time.
**Impact:** farmer income uplift, households served during outages, outbreaks caught early, produce rescued from waste.
**Business:** monthly recurring revenue (plans and Radar), CAC and LTV by segment, drivers earning each week.

## 9. Unfair advantage

- **Verified, geo-tagged outbreak data.** Every confirmed case improves the map and the forecasts. A competitor starts with none.
- **A community voice the provider can act on.** Counted, one person one voice, with a public timeline from request to trucks.
- **FNB rails and identity.** Escrow, Instant Money and verified IDs are hard for a startup to replicate alone.
- **Built for the people who need it:** offline AI, isiZulu, SMS alerts, low data.
- **A working product** already in farmers' hands (Nolifa Grow), not a slide.
