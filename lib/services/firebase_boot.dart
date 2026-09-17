import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether Firebase actually came up.
///
/// The app ships before the Firebase console project exists, and a failed
/// init must not blank the screen — every cloud-backed feature checks this
/// and shows a setup notice instead of throwing.
class FirebaseBoot {
  static bool ready = false;
  static String? error;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
    } catch (e) {
      ready = false;
      error = e.toString();
    }
  }
}

final firebaseReadyProvider = Provider<bool>((ref) => FirebaseBoot.ready);
