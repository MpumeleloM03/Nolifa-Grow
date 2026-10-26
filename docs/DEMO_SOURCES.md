# Demo video: sources and what is real

The demo video is built around the problem statement, not the app: *how might communities use data and digital services to prepare for disruptions, reduce household costs and improve access to water, energy, transport and food* (FNB App of the Year 2026, "Climate resilience and essential services"). When a flood, drought or heatwave hits, water, food and roads fail together. Nolifa's job is to **warn early** and **keep essentials reaching people**.

Electricity and load shedding are out of scope by choice.

## Statistics on screen

| On screen | Source | Note |
| --- | --- | --- |
| 207 foot-and-mouth cases in KZN by Feb 2026, 187 unresolved | IOL Mercury, 11 Feb 2026 | News report, not an official count |
| 37.6% of households had water cut for 2+ days in 2025 | Stats SA General Household Survey 2025, as reported by BusinessDay, 27 May 2026 | Check the wording against the primary release before quoting |
| About a third of food grown in South Africa is wasted | WWF South Africa, Food Loss and Waste: Facts and Futures, 2017 | Nine years old. We have not measured waste reduced |
| 22.0% of households had inadequate food access in 2025 (17.8% in 2019) | Stats SA, General Household Survey 2025 media release, 26 May 2026 | |

## Real, seeded or test

| Beat | Status |
| --- | --- |
| Weather | Built with `QA_DEMO_FORECAST=true`: a made-up week (frost, a 36 degree day, heavy rain), and the card says "Demo forecast". The app shows real Open-Meteo data otherwise |
| Disease | The symptom check is guidance, not a diagnosis. The outbreak report is a real row on the shared map, shown as unconfirmed. An alert needs 2 verified farms to confirm |
| Water | Real DWS dam data, weekly. Vote needs a verified person; the demo community account is phone-verified for the demo |
| Cold chain | Stock and room readings are seeded and typed by hub staff, not live sensors. The alarm in the video is a real reading typed in the back office tool and restored afterwards |
| Roads | Live TomTom incidents refreshed every 5 minutes, not confirmed on the ground |
| Food access | A real test order. Payments run in Yoco test mode |
| Impact | The app lists what it can and cannot yet prove |

`tools/demo_hook.py`, `tools/record_scene.py` and `integration_test/demo_test.dart` re-record every scene.
