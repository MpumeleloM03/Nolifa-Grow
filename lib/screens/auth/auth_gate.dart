import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecondFactorGuard;
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
