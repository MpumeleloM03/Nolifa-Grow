# Security: what we built, what the backend must do

Four risks were raised by the team. Here is each one, what the apps do now, and what is still needed.

| # | Risk | What the apps do now | Still needed |
|---|---|---|---|
| 1 | 4-digit PIN can be guessed | 3 tries, then the order locks, a dispute opens and the money stays frozen until a mediator rules | Run the rules tests on the emulator. Mediator tooling |
| 2 | Escrow runs on the device | Rules say who may write what. The prototype still simulates the release | A licensed provider (FNB) holds the money and a server function releases it. See below |
| 3 | Personal data in local storage | Sealed with AES-256-GCM, key in the Keychain or Keystore | Server-side encryption and retention rules when the backend is on |
| 4 | One person, many accounts, many votes | Only verified people vote on water or confirm an outbreak | The backend issues the `verified` claim and allows one verified number per account |

## 1. Delivery PIN attempts
- A wrong PIN counts. The third wrong try locks the order, opens a dispute with the reason "Delivery PIN entered wrongly 3 times", and the payment stays frozen.
- Even the right PIN stops working once locked. A mediator decides. In the demo a pretend mediator refunds the buyer. Live, a person rules.
- The PIN is stored only as a salted hash in the shared order. The plain PIN stays on the buyer's phone.
- Rules (`firestore.rules`): the assigned driver can add one try at a time, cannot reset or skip the count, and the third try must open a `pinLocked` dispute in the same write. Tests are in `firebase/rules-tests/market.rules.test.js`. **They have not been run yet** because the emulator needs Java, which is not installed on the build Mac. Run `npm test` in `firebase/rules-tests` once it is.
- Code: `tryPin` in `market_store.dart`.

## 2. Escrow must not run on the device
**The problem.** Today the app decides when money moves. A modified app could release money early.

**The fix.** Money moves only on a server that a licensed provider controls.
1. The customer pays into an account held by FNB or another licensed provider, not by Nolifa and not on a phone.
2. A server function (for example a Cloud Function) is the only thing that can release funds.
3. The driver's phone sends the PIN to the server. The server checks the hash, counts the tries and either releases or locks. The phone never decides.
4. The server releases after the customer confirms, or after the protection window, unless a dispute is open.
5. Client writes to `released`, `status: delivered` and `deliveredAt` are removed from the rules, so a modified app cannot do it either.
6. Refunds and dispute outcomes are executed by the server from a mediator's decision.

**In the prototype** the release is simulated and labelled so (checkout, wallet, Trust and Safety). The fee, escrow and PIN rules are real and ready to move to the server.

## 3. Local data encryption
- What is sealed: market state (orders, KYC progress, profile, business and inspection), water data, accounts, the herd register, scan history, crop plots, community posts and supplier details.
- How: AES-256-GCM with a random nonce each time. A changed byte is detected. The key is generated once and kept in the iOS Keychain or Android Keystore, never next to the data.
- Older plain data is read once and sealed the next time it is saved. History lists are migrated and the plain copy deleted.
- If the key store is unavailable the app uses a temporary key for that run rather than writing plain text.
- Not sealed because they are not personal: language, appearance, onboarding flags, the cached weather forecast.
- Code: `packages/ubuntu_core/lib/security/secure_box.dart`. Tests: `test/secure_box_test.dart`.
- Still to do for POPIA: a retention and deletion policy, and a way for a person to export or delete their data.

## 4. Each person counts once
- **Outbreak confirmations:** only a verified farmer can confirm someone else's report.
- **Water votes:** only a verified member can vote: a verified farm, or a household whose phone number passed the one-time-code check. Changing the number removes the right until the new number is verified.
- Rules: votes and confirmations need `request.auth.token.verified == true`. The verification service sets that claim; a client cannot.
- Demo: the code is shown on screen ("Demo code"). Production sends an SMS.
- **Backend must also:** allow one verified number per account, and link verification to an ID for farms. Without this, one person could still verify five numbers.
- Open question for the team: the first note asked for verified farmers to vote on water. Households are the main water users, so households vote once their phone is verified. Confirm this is what we want.

## Other protections already in place
- Passwords are stored as salted hashes, never in clear.
- Locations in reports are rounded to about 5 km and placed by region.
- Delivery photos are needed at pickup and drop-off.
- Water votes: one per account per request, only when supply is Low or Critical, enforced by the database.
- Rules tests cover more than 100 cases (not run in this session, see above).

## Known gaps
- Rules tests unrun. Escrow and identity simulated. No App Check or rate limiting on the backend. The verification claim service does not exist yet.
