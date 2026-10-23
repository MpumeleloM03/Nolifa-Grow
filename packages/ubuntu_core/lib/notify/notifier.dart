import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puts a notification on the phone. The apps supply the real one (it needs a
/// plugin); the default does nothing, which is what tests and the web want.
abstract class NoticeSender {
  Future<void> show({required String title, required String body});
}

class SilentNotices implements NoticeSender {
  const SilentNotices();
  @override
  Future<void> show({required String title, required String body}) async {}
}

final notifierProvider = Provider<NoticeSender>((ref) => const SilentNotices());

/// Set once the welcome-back notification has gone out in this run, so opening
/// a second screen does not send another.
final welcomeShownProvider = StateProvider<bool>((ref) => false);
