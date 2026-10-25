import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecondFactorGuard;
import '../../edition.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../shell/grow_shell.dart';
import 'login_screen.dart';

/// Decides whether the app opens on sign-in or the mode chooser.
///
/// Works the same whether accounts are coming from Supabase or from local
/// storage — [AuthService] hides which one is live.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          loading: () => const _Splash(),
          // A failed session check is never a dead end: sign-in still works.
          error: (_, __) => const LoginScreen(),
          data: (user) => user == null
              ? const LoginScreen()
              : AppEdition.isGrow && !user.isFarmer
                  ? WrongAppScreen(who: user.isDriver ? 'a driver' : 'a community member')
                  : SecondFactorGuard(key: ValueKey('2fa-${user.uid}'), child: const GrowShell()),
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: Center(child: CircularProgressIndicator(color: AppTheme.sprout)),
      ),
    );
  }
}

/// Nolifa Grow is for farmers. Someone who signed up as something else is told
/// where to go instead of being dropped into a screen that does not fit them.
class WrongAppScreen extends ConsumerWidget {
  final String who;
  const WrongAppScreen({super.key, required this.who});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.s6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: GlassCard(
                  padding: const EdgeInsets.all(AppTheme.s6),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.agriculture_rounded, color: AppTheme.sprout, size: 40),
                    const SizedBox(height: AppTheme.s3),
                    Text('Nolifa Grow is for farmers', style: AppTheme.title2),
                    const SizedBox(height: AppTheme.s2),
                    Text(
                      'This account is $who. Open Nolifa, which has a place for every role, or the app made for you: Nolifa Drop for households, Nolifa Delivery for drivers.',
                      style: AppTheme.callout,
                    ),
                    const SizedBox(height: AppTheme.s5),
                    GlassButton(
                      label: 'Sign out',
                      icon: Icons.logout_rounded,
                      onPressed: () => ref.read(authServiceProvider).signOut(),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
