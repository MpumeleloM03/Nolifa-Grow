# One backend, three doors

Drop, Grow and Delivery share one Supabase project. Each app talks to its own door, so a household only sees what a household needs.

| Door | Schema | Who | What it shows |
| --- | --- | --- | --- |
| Drop | `drop_api` | Households | `farms()`: each farm and what it has in stock. `track_order(id)`: where my order is and where the driver is, live. |
| Grow | `grow_api` | Farmers | `my_inventory()`: shop stock beside what the warehouse holds and how cold the room is. `request_truck`, `accept_truck`, `cancel_truck`, `truck_estimate`, `my_trucks`, `my_notifications`. |
| Delivery | `delivery_api` | Drivers | `post_location`, `go_offline`, `my_payouts`. |

The door functions run as the signed-in person and check who they are. Row level security on the tables underneath stays on, so a call that skips a door still sees nothing it should not.

## What happens, in order
1. A farmer adds stock (Sell tab). It is written to `market_products` at once, or queued if there is no signal.
2. Drop reads the same live list, so the household sees the farm and its stock change without a refresh.
3. A household places an order. The server prices it, takes the stock off the shelf and holds it until the card payment (Yoco) goes through. Cash orders skip that step.
4. The farm gets a notice. After payment, the farm packs it, prints the parcel label and scans it to send it out. A driver now sees the job.
5. The driver app posts a position while the driver is online. The household and the farm see the driver on a map for that order only.
6. The customer PIN closes the delivery and releases the money (farm, driver and Nolifa shares).

## Farm logo and store picture
A farm uploads a logo and a store picture with its application (both required; the server refuses a submit without them). They go to the public `farm-brand` bucket, in the farm's own folder. When Nolifa approves the farm, `review_application` copies them into the public `farm_profiles` row. Every phone and the back office follow that table live, so Drop shows the farm's logo and picture as soon as it is approved, and the back office stock table shows the logo beside the farm name. An approved farm can change them later in Settings (`set_farm_brand`). Farms with no picture keep the drawn badge.

## Switching plan by card
A farm taps a plan in Plans and pays through Yoco. The server holds the price (`plan_price_cents`, `PLAN_CENTS` in `yoco-checkout`), and only Yoco's signed message can switch the plan on (`activate_plan_paid`). The plan changes in `seller_plans` at once, the phone follows it live (no refresh), the farm gets a notice, and the change is written to `plan_changes`. The back office Plans page lists every switch (by card or by staff). This charges one month; nothing bills the farm again next month yet.

## Approval and notices
Approving a farm or a driver, a plan, a membership or a payout writes a row in `notifications`. The phone listens to that table live, shows the notice, and unlocks the paid features without a restart.

## Temperature
Hub staff post readings to `warehouse_readings`. A trigger keeps `room_climate` current and raises a notice for the farmers who store in that room when it is out of range. Farmers read only the rooms they have stock in.

## Real or demo
Fatboy Butcheries is a real seller account with a verified application and a paid plan. Its lots and room readings were put in by `tools/seed_fatboy.py` for the pitch and are labelled "Demo stock for the pitch". Live readings from a probe are not connected yet.
