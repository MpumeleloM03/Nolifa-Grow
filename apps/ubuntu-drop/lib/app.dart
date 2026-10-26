import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'onboarding/onboarded.dart';
import 'onboarding/onboarding_screen.dart';
import 'services/tracking_map.dart';
import 'shell/drop_hub.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Plugs the shared package into this app's sign-in and storage.
///
/// Before sign-in nothing is saved anywhere. Once signed in, data goes to
/// Supabase when it is connected and stays on the phone when it is not.
final List<Override> dropOverrides = [
  ...liveOverrides(() => SupabaseBoot.ready),
  trackMapProvider.overrideWithValue((order) => TrackingMap(order, key: ValueKey(order.id))),
  marketUidProvider.overrideWith(
    (ref) => ref.watch(currentUserProvider.select((u) => u?.uid)) ?? 'guest',
  ),
  marketNameProvider.overrideWith(
    (ref) =>
        ref.watch(currentUserProvider.select((u) => u?.name)) ?? 'Neighbour',
  ),
  marketRepositoryProvider.overrideWith((ref) {
    if (_signedOut(ref)) return LocalMarketRepository.memory();
    return ref.watch(supabaseReadyProvider)
        ? SupabaseMarketRepository()
        : LocalMarketRepository();
  }),
  waterRepositoryProvider.overrideWith((ref) {
    if (_signedOut(ref)) return LocalWaterRepository.memory();
    return ref.watch(supabaseReadyProvider)
        ? SupabaseWaterRepository()
        : LocalWaterRepository();
  }),
  waterUtilityProvider.overrideWith(
    (ref) => ref.watch(utilityClaimProvider).valueOrNull ?? false,
  ),
];

bool _signedOut(Ref ref) =>
    ref.watch(currentUserProvider.select((u) => u == null));

/// The app root: follows the phone's light/dark setting or the in-app choice, then the sign-in gate.
class NolifaDropApp extends StatelessWidget {
  const NolifaDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppearanceScope(
      builder: (context, light, dark, mode) => MaterialApp(
        title: 'Nolifa Drop',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        // Status bar icons follow the active palette.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppearanceScope.overlay,
          child: LanguageScope(child: OfflineOverlay(child: child!)),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// Signed out: sign-in. Signed in: the welcome cards once, then the hub.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref
        .watch(authStateProvider)
        .when(
          loading: () => const _Splash(key: ValueKey('splash')),
          error: (e, _) {
            debugPrint('auth: could not read sign-in state: $e');
            // Never a dead end: sign-in still works.
            return const LoginScreen(key: ValueKey('login'));
          },
          data: (user) {
            if (user == null) return const LoginScreen(key: ValueKey('login'));
            final seen = ref.watch(onboardedProvider(user.uid));
            if (!seen.hasValue) return const _Splash(key: ValueKey('splash'));
            if (!seen.requireValue) {
              return OnboardingScreen(
                key: const ValueKey('onboarding'),
                onDone: () =>
                    ref.read(onboardedProvider(user.uid).notifier).finish(),
              );
            }
            return SecondFactorGuard(key: ValueKey('2fa-${user.uid}'), child: const DropHub(key: ValueKey('hub')));
          },
        );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: page,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💧', style: TextStyle(fontSize: 48)),
                const SizedBox(height: AppTheme.s4),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.sprout,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
