# Nolifa Delivery

The driver app for Nolifa. Pick up orders from farms nearby, bring them to the
customer, and get paid when the customer gives the 4-digit PIN. Drivers keep 80%
of the delivery fee. Shares its engine with Nolifa Grow and Nolifa Drop through
`packages/ubuntu_core` in the `nolifa-ios` project.

Tabs: Jobs, Earnings, Account (verification, details, sign out).

## Run

```
flutter pub get
flutter run
```

Without a Supabase connection the app runs in Local mode: accounts and data stay on
the phone. See `nolifa-ios/docs/SUPABASE_SETUP.md` to connect the backend. The
Supabase files in this project were copied from Nolifa Drop and must be replaced
when `com.nolifa.delivery` is registered.

## Test

```
flutter analyze
flutter test
```
