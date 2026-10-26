# The four Nolifa apps

One backend (Supabase "Nolifa Suite"), four apps.

| App | For | Where it lives | Android id | iOS bundle id |
| --- | --- | --- | --- | --- |
| **Nolifa** | Everyone, in one app: farm, delivery and the marketplace | this repo, `lib/main.dart` | `com.nolifa.app` | `com.nolifa.app` |
| **Nolifa Grow** | Farmers only | this repo, `lib/main_grow.dart` | `com.nolifagrow.nolifa_grow` | `com.nolifagrow.nolifaGrow` |
| **Nolifa Drop** | Households that buy | `~/ubuntu-drop` | `com.ubuntudrop.ubuntu_drop` | `com.ubuntudrop.ubuntuDrop` |
| **Nolifa Delivery** | Drivers | `~/nolifa-delivery` | `com.nolifa.delivery` | `com.nolifa.delivery` |

Nolifa and Nolifa Grow are two flavors of one code base (`lib/edition.dart`). Grow does not offer the community or driver roles at sign-up, and an account that is not a farmer is told which app to use instead. Both share the same screens, the same offline outbox and the same Supabase doors (`docs/APP_DOORS.md`), so a farmer's stock, orders and plan look the same in either app.

## Build
```bash
# Android
flutter build apk --release --flavor nolifa -t lib/main.dart
flutter build apk --release --flavor grow   -t lib/main_grow.dart

# iOS (simulator)
flutter build ios --simulator --flavor nolifa -t lib/main.dart
flutter build ios --simulator --flavor grow   -t lib/main_grow.dart
```
Run with `flutter run --flavor grow -t lib/main_grow.dart`. A build without `--flavor` does not work.

## Logos
The app is called Nolifa Grow and its logo is the two-leaf mark, in both builds. Phone icons: `assets/icons/` (Android, from `flutter_launcher_icons-*.yaml`) and `ios/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset` (light and dark).
