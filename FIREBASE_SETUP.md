# Firebase setup — Nolifa Grow

The app builds and runs without Firebase, but shows a "Firebase not connected"
screen until these steps are done. Accounts, community chat, the herd register
and the outbreak heat map all depend on it.

Budget about 20 minutes.

---

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and sign in with your Google account.
2. **Add project** → name it `nolifa-grow` → Continue.
3. Google Analytics is optional. Skip it unless you want it.
4. Wait for provisioning, then **Continue**.

## 2. Turn on Email/Password sign-in

1. Left sidebar → **Build** → **Authentication** → **Get started**.
2. **Sign-in method** tab → **Email/Password** → toggle **Enable** → **Save**.

Leave "Email link (passwordless)" off — the app does not use it.

## 3. Create the Firestore database

1. Left sidebar → **Build** → **Firestore Database** → **Create database**.
2. Choose **Start in production mode**. (Rules get replaced in step 6.)
3. Pick location **`europe-west1`** or **`europe-west3`** — lowest latency to South Africa.
4. **Enable**.

## 4. Install the tooling

You only do this once per machine.

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

If `flutterfire` is not found afterwards, add the pub bin directory to your PATH:

```bash
echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.zshrc && source ~/.zshrc
```

## 5. Connect the app

```bash
firebase login
cd /Users/kingmidus/nolifa-ios
flutterfire configure --project=nolifa-grow
```

At the prompts:

- **Platforms** — select **ios** and **android** (space to toggle, enter to confirm).
- **iOS bundle ID** — accept `com.nolifagrow.nolifaGrow`.

This writes `lib/firebase_options.dart` and `ios/Runner/GoogleService-Info.plist`.
Both are generated — do not edit them by hand.

Then point `main.dart` at the generated options:

```dart
// lib/services/firebase_boot.dart — inside init()
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

with `import 'package:nolifa_grow/firebase_options.dart';` at the top.

## 6. Publish the security rules

The repo has `firestore.rules` already written. It keeps each farmer's herd
private, lets any signed-in user read and post in regional chat, and makes
outbreak reports append-only.

```bash
cd /Users/kingmidus/nolifa-ios
firebase deploy --only firestore:rules
```

If it asks which project, pick `nolifa-grow`.

> Do not skip this. Firestore's default production rules deny everything, so the
> app will look broken — chat empty, herd won't save — until the rules are live.

## 7. Run it

```bash
flutter run
```

You should land on the sign-in screen instead of the setup notice. Create an
account, and check the Firebase console → Authentication → Users to confirm it
arrived.

---

## Checking it works

| What | Where to look |
|---|---|
| Account created | Console → Authentication → Users |
| Profile saved | Console → Firestore → `users/{uid}` |
| Chat message posted | Console → Firestore → `chatRooms/{region}/messages` |
| Animal added | Console → Firestore → `users/{uid}/cattle` |
| Diagnosis on the map | Console → Firestore → `outbreaks` |

## If something breaks

**"Firebase not connected" after step 5** — `firebase_options.dart` was not
generated, or `firebase_boot.dart` was not updated to pass the options. Check
both exist and rebuild with `flutter clean && flutter run`.

**Chat and herd stay empty, no error** — rules were not deployed (step 6).

**`PERMISSION_DENIED` in the console output** — you are signed out, or the rules
deployed to a different project than the app is pointed at.

**`GoogleService-Info.plist` missing from Xcode** — reopen
`ios/Runner.xcworkspace`, and confirm the file sits under the `Runner` group. If
not, drag it in and tick "Copy items if needed".

---

## Cost

Everything here runs on the Spark (free) plan: 50k document reads, 20k writes and
1 GiB stored per day. A few hundred farmers chatting and logging herds stays well
inside that. You would only need the paid Blaze plan for Cloud Functions or
Storage-heavy photo uploads.

---

# Nolifa Drop (marketplace) on Firebase

Nolifa Drop works with no Firebase at all: everything is saved on the phone. Once
steps 1 to 6 above are done it switches itself to Firestore and **orders,
listings and outbreak cases are shared between phones in real time**. No code
change is needed. The rules from step 6 already include the marketplace.

## What lives where

| Collection | Contents | Who can read |
|---|---|---|
| `marketProfiles/{uid}` | Balances, plan, verification checks, ledger | Only that user |
| `marketProducts/{id}` | Produce listed by farmers | Any signed-in user |
| `marketOrders/{id}` | Orders. Delivery PIN is stored as a hash only | Buyer, farmer, driver; open jobs to any signed-in driver |
| `marketCases/{id}` | Outbreak reports and verification stage | Any signed-in user |

## Demo mode and live mode

Open **Trust & Safety** (shield icon) and use the **App mode** switch.

- **Demo mode (default):** seeded farms, simulated neighbour drivers and a
  12-second protection window, so one person can watch the whole loop.
  Orders from demo farms stay on the phone and never reach Firestore.
- **Live mode:** only real people and real listings, with the real 2-hour window.

To show the real multi-phone flow with two phones signed into two accounts:
a farmer lists produce, a buyer orders it, the farmer packs it, a driver on a
third phone claims it, collects, enters the buyer's PIN, and the buyer confirms.
Each phone shows its own side of the same order.

## Test the rules (no Firebase project needed)

The rules are tested in the local Firestore emulator. It needs Java.

```bash
brew install openjdk@21
export JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH
cd firebase/rules-tests
npm install
npm test
```

You should see 38 tests pass: 37 allow/deny cases, plus one that replays every
write the real app makes.

If you change what the app writes, regenerate the recorded writes first:

```bash
flutter test test/export_rules_fixture_test.dart
```

## Special accounts: mediators and vets

Disputes and vet verification are decided by people with a custom claim that
only trusted admin code can set. Grant one with the Firebase Admin SDK, for
example in a one-off Node script:

```js
await admin.auth().setCustomUserClaims(uid, { mediator: true }); // or { vet: true }
```

The staff consoles that use these claims are not built yet (see `docs/SSDLC.md`,
section 5). Until then, live disputes wait in review.

## Not done yet (be honest about this with judges)

- Order totals are calculated on the phone. A trusted backend (Cloud Functions,
  needs the Blaze plan) should recompute them and settle money.
- Payments, ID checks and mediation are simulated.
- Escrow release is timed by whichever phone is open; a scheduled function
  should do it.

Full list and plan: `docs/SSDLC.md`.
