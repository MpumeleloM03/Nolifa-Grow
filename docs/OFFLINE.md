# Working without signal

Nolifa is built for patchy signal. What works with none, and what does not.

## Works offline
| Feature | How |
| --- | --- |
| Leaf scanner | The model is on the phone (`assets/models/plant_model.tflite`). With signal and a Plant.id allowance the app asks Plant.id first (through the `plant-id` function, so the key stays on the server). With no signal, no allowance or no key it uses the phone model and says so: "less accurate". |
| Water radar | Dam levels are saved after each load (`dws_kn_report`). Shared water zones, incidents and the person's own votes are saved by the live-list cache. |
| Road alerts | TomTom incidents are saved by the live-list cache and each row still shows its age. |
| Weather and herd alerts | The last 7-day forecast per place is saved (`forecast_<place>`). The screen says "Saved forecast". |
| Herd register, care reminders, crop plots, sprinkler plans | Stored on the phone. Reminders are local notifications. |
| Orders, wallet, saved scans | Last copy is shown from the cache. |

## How the cache works
`resilientRows` keeps the latest rows of every shared list in `shared_preferences` under `offline:v1:<user>:<table>` (max 600 KB per list). On start the saved rows show at once; live data replaces them as soon as the network answers. Sign-out wipes every copy. A small pill at the top of each app says "Offline. Saved data from HH:MM." while live data is not arriving.

## Needs signal, or another person
- Placing or paying for an order, a PIN handover, a vote, a vet video upload, a membership payment.
- Map tiles (OpenStreetMap) and routing.
- Push for a closed app. Email alerts work; phone push needs the store builds.
- SMS or USSD fallback for feature phones is not built.

## Honest limits
- A saved copy can be old. The pill shows its time; do not act on a road alert without checking its age.
- Writes made while offline are not queued. The app says it could not send them.
