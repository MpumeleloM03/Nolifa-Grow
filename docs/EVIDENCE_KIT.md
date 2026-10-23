# Evidence kit: what we owe the judges

The criticism was fair: no farmer testing, no measured accuracy, no cost savings, no crop-loss figures. This kit shows how to collect honest numbers quickly. Report what you get, even if it is small.

## 1. Leaf scanner accuracy (2 days)
**Goal:** the real accuracy of the scanner on KZN photos.

1. Collect 50 to 100 photos of real leaves, including healthy ones. Ask an extension officer or a farmer who knows the disease to name each one. That name is the label.
2. Put them in `labels.csv`: `photo,true_label` (use the exact names in `lib/models/disease_info.dart`, for example `Late_Blight`, `Healthy`).
3. Run each photo through the app's scanner (camera or gallery) and write what it said in `predictions.csv`: `photo,predicted_label`.
4. Run `python3 tools/scanner_eval.py labels.csv predictions.csv`.
5. Report: overall accuracy, accuracy per disease, and the number of photos. If accuracy is low on a disease, say so and say what the app does about it (it is a guide and sends people to a vet or officer).

## 2. Farmer interviews (1 week, 10 farmers)
Keep it short, 20 minutes, with consent. Ask:
1. What went wrong on your farm last season? How much did you lose?
2. How did you find out, and how late was it?
3. Show the scanner on their own plant. Did the answer match what they know?
4. Which of these would you use: scanner, cattle checker, water warning, selling to neighbours?
5. Would you pay R49 a month to sell? What would make it worth it?
6. What would stop you using it (signal, data cost, language, trust)?
Record answers in `interviews.csv`. Quote one farmer by name only with permission.

## 3. Small trial (2 to 4 weeks)
5 farms and 20 households in one area, or one co-op. Measure: orders placed, deliveries completed, time from water vote to answer, disputes, and what the farmers earned. Report the numbers with the sample size.

## 3b. Measured inside the app
The Impact page (Settings, Impact evidence) collects evidence while farmers use the app, so a trial needs no extra forms: scan verdicts with an interval, forecast against observed weather, harvest date against the prediction, and water saved by rain. Export it as CSV from the page and attach it to the results. Report the number of cases next to every figure. Under 30 cases the app says "too few to claim", and so should we.

## 4. What not to claim
- Do not claim a number of farmers, savings or reduced losses without a source or a measurement.
- Say "free" only for what is free (see the free vs paid card in the app).
- Say the AI is a guide, not a diagnosis.

## 5. Where to put the results
Add them to the pitch and `docs/VALIDATION_PLAN.md`. A small honest result beats a large claim.
