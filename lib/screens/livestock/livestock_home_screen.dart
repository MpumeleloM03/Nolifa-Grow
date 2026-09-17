import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cattle.dart';
import '../../services/cattle_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import 'herd_screen.dart';
import 'symptom_checker_screen.dart';

class LivestockHomeScreen extends ConsumerWidget {
  const LivestockHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final herd = ref.watch(herdProvider);

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Livestock'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(
                  children: [
                    herd.when(
                      loading: () => const _HerdSummary(total: null),
                      error: (_, __) => const _HerdSummary(total: null),
                      data: (list) => _HerdSummary(
                        total: list.where((c) => c.status == CattleStatus.active).length,
                        breakdown: _countBySex(list),
                      ),
                    ),
                    const SizedBox(height: AppTheme.s4),
                    _ActionCard(
                      title: 'Herd register',
                      subtitle: 'Add animals, import tags, export your records',
                      icon: Icons.list_alt_rounded,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HerdScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: AppTheme.s3),
                    _ActionCard(
                      title: 'Check symptoms',
                      subtitle: 'Tick what you see and get guidance',
                      icon: Icons.medical_services_outlined,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SymptomCheckerScreen()),
                        );
                      },
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

  static Map<String, int> _countBySex(List<Cattle> list) {
    final counts = <String, int>{};
    for (final c in list.where((c) => c.status == CattleStatus.active)) {
      counts[c.sex] = (counts[c.sex] ?? 0) + 1;
    }
    return counts;
  }
}

class _HerdSummary extends StatelessWidget {
  final int? total;
  final Map<String, int> breakdown;

  const _HerdSummary({required this.total, this.breakdown = const {}});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On the farm', style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                total?.toString() ?? '—',
                style: AppTheme.largeTitle.copyWith(
                  fontSize: 48,
                  color: AppTheme.livestockAccent,
                ),
              ),
              const SizedBox(width: AppTheme.s2),
              Text('head of cattle', style: AppTheme.callout),
            ],
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: AppTheme.s4),
            Wrap(
              spacing: AppTheme.s2,
              runSpacing: AppTheme.s2,
              children: breakdown.entries
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.s3, vertical: AppTheme.s1),
                        decoration: BoxDecoration(
                          color: AppTheme.glassFill,
                          borderRadius: BorderRadius.circular(AppTheme.rChip),
                          border: Border.all(color: AppTheme.glassBorderSoft),
                        ),
                        child: Text('${e.value} ${e.key}',
                            style: AppTheme.caption
                                .copyWith(color: AppTheme.textSecondary)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.s5),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.livestockAccent, size: 24),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.headline),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTheme.footnote),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textTertiary, size: 20),
        ],
      ),
    );
  }
}
