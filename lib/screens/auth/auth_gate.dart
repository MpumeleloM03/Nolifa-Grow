import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../mode_select_screen.dart';
import 'login_screen.dart';

/// Decides whether the app opens on sign-in or the mode chooser.
///
/// Works the same whether accounts are coming from Firebase or from local
/// storage — [AuthService] hides which one is live.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
