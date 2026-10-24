# Water: what is real today, and how to make the rest real

## Real today
- **Dam levels.** The app reads the weekly State of Dams table from the Department of Water and Sanitation (DWS) for KwaZulu-Natal. Midmar, Albert Falls, Nagle, Inanda, Hazelmere and the rest show their real percentage full, this week and last week.
- **Supply systems.** Durban/Pietermaritzburg and the North Coast are worked out from the dams that feed them, weighted by capacity.
- **Forecast.** Holt smoothing over the weekly change, then adjusted with Open-Meteo rain: 50 mm or more ahead turns a fall around, 25 mm halves it, a dry hot week speeds it up. Confidence is capped at 0.35 because we only have two weekly points.
- **Weather.** 7-day Open-Meteo forecast drives heat, frost, storm and dry-spell alerts and the sprinkler advice.
- **Cache.** The last good report is stored on the phone and used offline. The screen says where each number came from.

- **Cloud copy.** The same five supply systems are stored in Supabase (`water_zones`, ids `dws-*`) by the `water-dams` function, so every phone shares one set of zones and one set of votes. DWS answers 403 to data-centre addresses outside South Africa, so `tools/sync_water.sh` fetches the page from a South African connection (a launchd job on the founder's Mac, daily 07:00 and at login) and posts it to the function. The phone still reads DWS itself and keeps the last good report for offline use.
- **Dry taps.** Dams are bulk storage. Any verified person can report dry taps even when the dam is full; `water_vote` takes a reason (`low_supply` needs under 40%, `dry_taps` does not). It still takes `voteThreshold` different verified people (10 by default, the provider can change it) before the request reaches the provider.
- **Provider desk.** Nolifa Drop shows the desk to an account whose token carries `utility` (set by staff, never by the app).

## Not real yet (and labelled)
- **Tap-level outages.** DWS publishes dams, not taps. Whether your street has water is not in any public feed.
- **Municipal restrictions and planned shutdowns.** eThekwini and uMgungundlovu post these as notices and social posts, not as data.
- **Household votes.** The demo seeds are simulated. Live votes need the Supabase backend.

## Road map
1. **Backend job (done, with one gap).** The `water-dams` function parses and stores the report. The fetch has to come from South Africa; move `tools/sync_water.sh` from the founder's Mac to a small South African server before launch. Add a second province per release.
2. **Municipal readings (month 1).** Ask eThekwini Water and Sanitation and uMngeni-uThukela Water for a read-only feed of reservoir levels and planned shutdowns. Until then, the provider desk lets a verified municipal user post it by hand.
3. **Household reports as signal (month 1-2).** Dry-tap and low-pressure reports from verified phones, rounded to about 5 km, become the tap-level layer. A zone turns amber when three or more verified households in it report in 24 hours.
4. **Local sensors (month 3+).** A R300 ultrasonic tank sensor with an ESP32 posts litres to the farm record. Farm tanks become measured instead of typed.
5. **Accuracy loop.** The Impact screen already compares each forecast to the next DWS report. Publish the running error. Retune the rain thresholds when 12 weeks of pairs exist.
6. **Other provinces and DWS gauges.** DWS also publishes river flow gauges. Add them for farm abstraction warnings.

## Honest limits
- A weekly feed cannot predict a burst main.
- Rain over the catchment is approximated with a few points per region.
- The forecast is a trend with a rain correction, not a hydrological model.
