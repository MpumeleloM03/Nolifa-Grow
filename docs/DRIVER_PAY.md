# Driver pay

Before: 80% of the buyer's delivery fee, worked out on the driver's phone. A 5 km trip paid R12.

Now: pay follows the work.

- **R12 per delivery** (collect, hand over, PIN) **plus R2.50 per road km**, never under **R24**.
- Local trips use the order's farm-to-door distance, capped by what the fee could have bought (so an inflated distance gains nothing). Hub orders are paid for the last mile only (R35 buys 30 km; each km beyond adds R1).
- Fuel is not added on top. R2.50 a km is meant to cover R1.90 of fuel plus wear. The batch screen shows pay per hour before and after fuel.
- The buyer's fee pays towards it. Nolifa tops up the rest, from the service fee and commission. The top-up is recorded per delivery.

## On the server
`driver_job_pay(order)` is the formula. `deliver_with_pin` writes a row to `driver_payouts` when the PIN is accepted (amount, base, distance part, minimum top-up, Nolifa top-up, km). The driver can read their own rows and nothing writes them but the server. The row is `released` when the order is released (customer confirms, or after 2 hours) and `cancelled` to R0 after a full refund or a driver-conduct dispute.

The Dart copy is `packages/ubuntu_core/lib/delivery/driver_pay.dart`. Both are pinned to the same numbers by `supabase/tests/database/driver_pay.test.sql` and `packages/ubuntu_core/test/driver_pay_test.dart`.

## What it costs Nolifa (sample)
| Trip | Driver is paid | Buyer fee | Nolifa tops up |
| --- | --- | --- | --- |
| 5 km local | R24.50 | R15 | R12.50 |
| 8 km local | R32.00 | R25 | R12.00 |
| 20 km local | R62.00 | R45 | R26.00 |
| Run of eight 8 km drops | R256 (about R80 an hour after fuel) | R200 | R96 |

Per order the platform keeps the 3% service fee (R2 to R15) plus 3 to 8% commission, so short low-value orders lose money. Batching, a minimum basket and a higher short-trip fee are the levers. Rates are constants (SQL and Dart) until a driver-pay config table is added.
