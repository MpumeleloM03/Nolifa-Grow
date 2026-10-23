# Land and crop inspection: how a farm starts selling

**The idea:** a surveyor checks a farm's land and crops before it sells. **Is it a good idea for rural communities?** As a hard gate, no. A surveyor first would shut out the farms Nolifa most wants to reach:

- Distance and cost. One visit can mean a day of travel for the inspector, and a long wait for a smallholder.
- Waiting means no income. A tomato farmer who waits six weeks for a visit misses the season.
- Low-risk produce (whole fresh vegetables and fruit) carries far less food-safety risk than eggs, milk or processed food. The same rule for both is too strict for one and too loose for the other.
- Urban farms near a town do not have this problem. A rule built around them would fail elsewhere.

**What the app does instead.** Inspection is required, but the order and the route change with the risk and the place.

| Step | What happens |
|---|---|
| 1. Register | Individual, co-op or company |
| 2. Verify | ID, payout account, farm location |
| 3. Plan | Monthly platform fee, includes support |
| 4. Show your land | Geo-tagged photos of the field, the crop and the water source. Photos are taken with no signal and sent when there is one (the upload needs the backend) |
| 5. Selling with limits | Opens at once after step 4 |
| 6. On-site inspection | Passes within 45 days, and the limits lift |

**While waiting for the inspection (selling with limits):**
- Fresh whole produce only. Eggs, milk and processed goods (the categories Dairy and Essentials) wait until the inspection passes.
- Up to R2 000 of sales. After that, new listings pause until the inspection passes.
- 45 days to complete it.

**Three ways to be inspected**, so no farm is stranded:

| Route | Best for | Usual wait |
|---|---|---|
| Surveyor visit | Farms near towns | 14 days |
| Extension officer | Rural farms with a local officer, often free | 7 days |
| Co-op inspection day | Villages and co-ops. One visit covers many farms | 21 days |

**If it fails,** listings pause. The inspector's notes say what to fix, and the farm books again.

**In the prototype** the visit date is an estimate and a demo button simulates the inspector's result. Live, only the inspection backend writes the result (see `FIREBASE_HANDOFF.md`). The rules are in `packages/ubuntu_core/lib/market/market_models.dart` (`Inspection`) and `market_store.dart` (`canSell`, `listBlock`).
