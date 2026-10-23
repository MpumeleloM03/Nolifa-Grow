# Validation plan: business model and operations

The prototype does not move real money, check real identities or talk to a real water provider. These are the things to test before anyone relies on them.

## Prices (R49, R99, R199 a month, plus commission)
These are hypotheses. Free for everyone: scanning, symptom checks, the water radar, alerts, community, buying. Only selling has a plan.

| Test | How | Pass if |
|---|---|---|
| Willingness to pay | Interview 30 smallholders and 10 co-ops across two districts. Show the free vs paid screen | At least 40% would pay R49 to sell, and understand what it buys |
| Break-even | Track real baskets in a pilot | A typical farm clears the plan with a few baskets a month |
| Commission | Compare against what farmers pay middlemen today | Total cost is lower than the middleman cut |
| Fallback | Offer a co-op plan paid once by the co-op | Co-ops accept it for members who cannot pay |

## Operations that must be real before launch
| Area | What must exist | Prototype today |
|---|---|---|
| Payments and escrow | FNB holds funds, settles to farm and driver, handles refunds | Simulated |
| Identity and bank checks | FNB and Home Affairs services | Demo buttons |
| Inspection | Surveyors, extension officers, co-op days with a roster and a result API | Simulated result |
| Water provider | A signed agreement, a readings feed, a named person to answer requests | Simulated feed and replies |
| Disputes | Mediators, a service level (48 hours) and an audit trail | Simulated |
| Support | A contact route for farmers with little data | Not built |

## Pilot
One district, 20 farms, 100 households, 10 drivers, 1 water provider, 8 weeks. Measure: orders per week, delivery success, dispute rate and time to resolve, time from water vote to truck, outbreaks caught early, and farmer income change.

## Reporting
Every screen that shows something simulated says so (checkout, wallet, verification, inspection, water readings, Trust and Safety). Nothing in the demo should look real that is not.
