# Nolifa Drop

Fresh food and community water for customers. Three tabs: Shop (farms with
their offerings, a cart), Water and Alerts, plus a menu for orders, wallet,
settings and help. Drivers use the separate Nolifa Delivery app. Shares its marketplace and water radar with
Nolifa Grow through `packages/ubuntu_core` in the `nolifa-ios` project.

## Run

```
flutter pub get
flutter run
```

Without a Supabase connection the app runs in Local mode: accounts and data stay
on the phone. To try the shared backend against the local emulators:

```
firebase emulators:start
flutter run --dart-define=FIREBASE_EMULATOR=true
```

## Test

```
flutter analyze
flutter test
```

## Water provider accounts

A signed-in account whose Supabase ID token carries the custom claim
`utility: true` gets the water provider desk. Everyone else can read supply,
get alerts and vote for help.
