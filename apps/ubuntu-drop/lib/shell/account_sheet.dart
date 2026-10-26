import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../auth/auth_service.dart';
import '../auth/auth_user.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// The small round button, top-left of every tab, that opens the account sheet.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Your account',
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          radius: 26,
          onTap: () {
            HapticFeedback.selectionClick();
            showAccountSheet(context);
          },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Avatar(user: user, size: 36)),
          ),
        ),
      ),
    );
  }
}

/// A circle with the person's first initial.
class Avatar extends StatelessWidget {
  final AuthUser user;
  final double size;
  const Avatar({super.key, required this.user, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.sprout.withValues(alpha: 0.5),
          AppTheme.leaf.withValues(alpha: 0.8),
        ],
      ),
      border: Border.all(color: AppTheme.glassBorder),
    ),
    child: Text(
      user.initial,
      style: AppTheme.headline.copyWith(fontSize: size * 0.44),
    ),
  );
}

/// Opens the account sheet: who you are, how to switch modes, sign out.
Future<void> showAccountSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AccountSheet(),
    );

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final demo = ref.watch(marketProvider.select((s) => s.demoMode));
    final shared = ref.watch(marketSharedProvider);
    final utility = ref.watch(waterUtilityProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s3),
        child: SingleChildScrollView(
          child: GlassCard(
            strong: true,
            padding: const EdgeInsets.all(AppTheme.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Avatar(user: user, size: 56),
                    const SizedBox(width: AppTheme.s4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.title3,
                          ),
                          if (user.email.isNotEmpty)
                            Text(
                              user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.footnote,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.s4),
                Wrap(
                  spacing: AppTheme.s2,
                  runSpacing: AppTheme.s2,
                  children: [
                    Pill(
                      shared
                          ? 'Synced between phones'
                          : 'Saved on this phone only',
                      color: shared ? AppTheme.sprout : AppTheme.textTertiary,
                      icon: shared
                          ? Icons.cloud_done_rounded
                          : Icons.phone_iphone_rounded,
                    ),
                    if (utility)
                      Pill(
                        'Water provider account',
                        color: AppTheme.sprout,
                        icon: Icons.water_drop_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.s5),
                GlassCard(
                  radius: AppTheme.rControl,
                  padding: const EdgeInsets.all(AppTheme.s4),
                  tint: (demo ? AppTheme.warn : AppTheme.sprout).withValues(
                    alpha: 0.10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        demo ? '🧪' : '🟢',
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              demo
                                  ? 'You are in demo mode'
                                  : 'You are in live mode',
                              style: AppTheme.headline,
                            ),
                            const SizedBox(height: AppTheme.s1),
                            Text(
                              demo
                                  ? 'Neighbours, drivers and the water provider are simulated so you can try everything.'
                                  : 'You only see real people, real listings and real water readings.',
                              style: AppTheme.footnote,
                            ),
                            const SizedBox(height: AppTheme.s2),
                            Text(
                              'To switch between demo and live mode, open Trust and Safety and use App mode.',
                              style: AppTheme.footnote,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.s4),
                GhostButton(
                  label: 'Open Trust and Safety',
                  icon: Icons.verified_user_rounded,
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TrustCenterScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppTheme.s3),
                const LanguagePicker(),
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  accent: AppTheme.danger,
                  onPressed: () {
                    // Grab the service first: this sheet is gone once it pops.
                    final auth = ref.read(authServiceProvider);
                    Navigator.of(context).pop();
                    auth.signOut();
                  },
                ),
                const SizedBox(height: AppTheme.s2),
                GhostButton(
                  label: 'Delete my account',
                  icon: Icons.delete_forever_rounded,
                  onPressed: () {
                    final auth = ref.read(authServiceProvider);
                    final nav = Navigator.of(context);
                    final host = nav.context;
                    nav.pop();
                    confirmDeleteAccount(host, auth.deleteAccount);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
