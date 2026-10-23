import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether Firebase actually came up.
///
/// The app ships before the Firebase console project exists, and a failed
/// init must not blank the screen — every cloud-backed feature checks this
/// and shows a setup notice instead of throwing.
/// Firebase is switched off by default: both apps run entirely on the phone.
/// The team member connecting the shared backend turns it on with
/// `--dart-define=USE_FIREBASE=true` (see docs/FIREBASE_HANDOFF.md).
const bool _useFirebase = bool.fromEnvironment('USE_FIREBASE');

class FirebaseBoot {
  static bool ready = false;
  static String? error;

  /// Points the app at the local Firebase emulators (Auth 9099, Firestore 8089)
  /// instead of the real project. Start them with `firebase emulators:start`,
  /// then run with `--dart-define=FIREBASE_EMULATOR=true`. Nothing is written
  /// to the real project.
  static void useEmulators({String host = 'localhost'}) {
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8089);
    FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }

  static Future<void> init() async {
    if (!_useFirebase) return; // stay in on-device mode
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (const bool.fromEnvironment('FIREBASE_EMULATOR')) useEmulators();
      ready = true;
    } catch (e) {
      ready = false;
      error = e.toString();
    }
  }
}

final firebaseReadyProvider = Provider<bool>((ref) => FirebaseBoot.ready);
