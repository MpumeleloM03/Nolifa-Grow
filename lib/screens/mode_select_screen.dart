import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show HomeScreen;
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'community_chat_screen.dart';
import 'livestock/livestock_home_screen.dart';
import 'map_screen.dart';

/// The app's home after sign-in. Crops and livestock are peers here, and every
/// downstream screen pops back to this, so switching between them is always
/// one gesture away.
class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = (user?.name.trim().isNotEmpty ?? false)
        ? user!.name.trim().split(' ').first
        : 'there';

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sawubona, $name', style: AppTheme.largeTitle),
                            const SizedBox(height: AppTheme.s1),
                            Text('What are you checking today?',
                                style: AppTheme.callout),
                          ],
                        ),
                      ),
                      _AccountButton(
                        onSignOut: () =>
                            ref.read(authServiceProvider).signOut(),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppTheme.s6),
                sliver: SliverList.list(
                  children: [
                    _ModeCard(
                      title: 'Crops',
                      subtitle: 'Photograph a leaf and get a diagnosis in seconds',
                      icon: Icons.eco_rounded,
                      accent: AppTheme.plantAccent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: AppTheme.s4),
                    _ModeCard(
                      title: 'Livestock',
                      subtitle: 'Track your herd and check cattle symptoms',
                      icon: Icons.pets_rounded,
                      accent: AppTheme.livestockAccent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LivestockHomeScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: AppTheme.s8),
                    Text('Your area', style: AppTheme.title3),
                    const SizedBox(height: AppTheme.s4),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickTile(
                            label: 'Outbreak map',
                            icon: Icons.map_outlined,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MapScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.s4),
                        Expanded(
                          child: _QuickTile(
                            label: 'Community',
                            icon: Icons.forum_outlined,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CommunityChatScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.s6),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rControl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.35),
                  accent.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Icon(icon, color: accent, size: 27),
          ),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.title2),
                const SizedBox(height: AppTheme.s1),
                Text(subtitle, style: AppTheme.footnote),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textTertiary, size: 22),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickTile(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          vertical: AppTheme.s5, horizontal: AppTheme.s4),
      radius: AppTheme.rControl,
      child: Column(
        children: [
          Icon(icon, color: AppTheme.sprout, size: 24),
          const SizedBox(height: AppTheme.s2),
          Text(label, style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  final VoidCallback onSignOut;
  const _AccountButton({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: 22,
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.person_outline_rounded,
            color: AppTheme.textPrimary, size: 22),
        color: AppTheme.forest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rControl)),
        onSelected: (v) {
          if (v == 'signout') onSignOut();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'signout',
            child: Row(
              children: [
                const Icon(Icons.logout_rounded,
                    size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: AppTheme.s3),
                Text('Sign out', style: AppTheme.subhead),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
