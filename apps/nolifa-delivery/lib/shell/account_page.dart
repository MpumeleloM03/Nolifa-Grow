import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../auth/auth_service.dart';
import 'delivery_hub.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Who the driver is, whether they are verified, and the account controls.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final left = driverSteps.length - s.driverKyc.length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '👤',
            title: 'Account',
            subtitle: 'Your details and verification',
            accent: AppTheme.livestockAccent,
            trailing: const HeaderActions(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: GlassCard(
                tint: (s.driverVerified ? AppTheme.sprout : AppTheme.warn).withValues(alpha: 0.12),
                onTap: () => _push(context, const VerifyScreen(role: KycRole.driver)),
                child: Row(children: [
                  Text(s.driverVerified ? '✅' : '🪪', style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.driverVerified ? 'You are verified' : 'Get verified to go online',
                          style: AppTheme.headline),
                      Text(
                          s.driverVerified
                              ? 'Customers and farms see your badge.'
                              : '$left ${left == 1 ? 'step' : 'steps'} left',
                          style: AppTheme.footnote),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                ]),
              ),
            ),
            const SizedBox(height: AppTheme.s4),
            const ProfileForm(),
            const SizedBox(height: AppTheme.s4),
            const AppearancePicker(),
            const SizedBox(height: AppTheme.s4),
            const LanguagePicker(),
            const SizedBox(height: AppTheme.s4),
            GhostButton(
              label: 'Trust and safety',
              icon: Icons.verified_user_rounded,
              onPressed: () => _push(context, const TrustCenterScreen()),
            ),
            const SizedBox(height: AppTheme.s3),
            GlassButton(
              label: 'Sign out',
              icon: Icons.logout_rounded,
              accent: AppTheme.danger,
              onPressed: () => signOutDriver(context, ref),
            ),
            const SizedBox(height: AppTheme.s2),
            GhostButton(
              label: 'Delete my account',
              icon: Icons.delete_forever_rounded,
              onPressed: () => confirmDeleteAccount(context, () => ref.read(authServiceProvider).deleteAccount()),
            ),
          ]),
        ),
      ],
    );
  }
}
