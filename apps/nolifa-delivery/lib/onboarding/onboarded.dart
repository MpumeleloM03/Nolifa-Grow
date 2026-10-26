import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _key(String uid) => 'onboarded_$uid';

/// Whether this person has been through the welcome cards on this phone.
/// Keyed by account, so a new neighbour on a shared phone still gets the tour.
class OnboardedNotifier extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String arg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(arg)) ?? false;
    } catch (e) {
      // Storage is unreadable. Showing the cards again is better than skipping them.
      debugPrint('onboarding: could not read flag: $e');
      return false;
    }
  }

  /// Remembers that the cards are done and moves the app on straight away.
  Future<void> finish() async {
    state = const AsyncData(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(arg), true);
    } catch (e) {
      debugPrint('onboarding: could not save flag: $e');
    }
  }
}

/// Whether the given account has finished the welcome cards.
final onboardedProvider =
    AsyncNotifierProvider.family<OnboardedNotifier, bool, String>(
      OnboardedNotifier.new,
    );
