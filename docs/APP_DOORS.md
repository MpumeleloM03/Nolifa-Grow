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

## Approval and notices
Approving a farm or a driver, a plan, a membership or a payout writes a row in `notifications`. The phone listens to that table live, shows the notice, and unlocks the paid features without a restart.

## Temperature
Hub staff post readings to `warehouse_readings`. A trigger keeps `room_climate` current and raises a notice for the farmers who store in that room when it is out of range. Farmers read only the rooms they have stock in.

## Real or demo
Fatboy Butcheries is a real seller account with a verified application and a paid plan. Its lots and room readings were put in by `tools/seed_fatboy.py` for the pitch and are labelled "Demo stock for the pitch". Live readings from a probe are not connected yet.
