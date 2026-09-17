import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_boot.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../mode_select_screen.dart';
import 'login_screen.dart';

/// Decides what the app opens on: setup notice, sign-in, or the mode chooser.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FirebaseBoot.ready) return const _SetupNeeded();

    return ref.watch(authStateProvider).when(
          loading: () => const _Splash(),
          error: (e, _) => _Splash(message: e.toString()),
          data: (user) =>
              user == null ? const LoginScreen() : const ModeSelectScreen(),
        );
  }
}

class _Splash extends StatelessWidget {
  final String? message;
  const _Splash({this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.sprout),
              if (message != null) ...[
                const SizedBox(height: AppTheme.s4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
                  child: Text(message!,
                      textAlign: TextAlign.center, style: AppTheme.footnote),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when Firebase has not been wired up yet, so the build is still
/// runnable and the remaining setup steps are visible in the app itself.
class _SetupNeeded extends StatelessWidget {
  const _SetupNeeded();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.s6),
              child: GlassCard(
                padding: const EdgeInsets.all(AppTheme.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 36, color: AppTheme.warn),
                    const SizedBox(height: AppTheme.s4),
                    Text('Firebase not connected', style: AppTheme.title2),
                    const SizedBox(height: AppTheme.s2),
                    Text(
                      'Accounts, community chat and the herd register all run on '
                      'Firebase. Run the setup steps, then relaunch.',
                      style: AppTheme.callout,
                    ),
                    const SizedBox(height: AppTheme.s5),
                    ...const [
                      'Create a Firebase project',
                      'Enable Email/Password sign-in',
                      'Create a Firestore database',
                      'Run: flutterfire configure',
                    ].indexed.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.sprout.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: Text('${e.$1 + 1}',
                                    style: AppTheme.caption
                                        .copyWith(color: AppTheme.sprout)),
                              ),
                              const SizedBox(width: AppTheme.s3),
                              Expanded(
                                  child: Text(e.$2, style: AppTheme.subhead)),
                            ],
                          ),
                        )),
                    if (FirebaseBoot.error != null) ...[
                      const SizedBox(height: AppTheme.s3),
                      Text(FirebaseBoot.error!,
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.textTertiary)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
