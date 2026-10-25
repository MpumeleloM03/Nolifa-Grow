import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show CaseCard, Reveal, SectionTitle, marketProvider;
import '../models/outbreak_report.dart';
import '../services/auth_service.dart';
import '../services/outbreak_service.dart';
import '../shell/alerts_tab.dart' show OutbreakTile, buildAreaOutbreaks;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'community_section.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// One place for everything the community is telling you: what neighbours
/// reported (like fall armyworm on maize), what is happening in your area and
/// elsewhere in KwaZulu-Natal, and the community chat, where every post is
/// backed by proof. Warnings about your own farm live under the alarm instead.
class CommunityAlertsScreen extends ConsumerWidget {
  const CommunityAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = ref.watch(currentUserProvider)?.region ?? '';
    final live = ref.watch(outbreaksProvider).valueOrNull ?? const <OutbreakReport>[];
    final all = buildAreaOutbreaks(live, demo: ref.watch(marketProvider.select((s) => s.demoMode)));
    final mine = all.where((o) => o.region == region).toList();
    final elsewhere = all.where((o) => o.region != region).take(6).toList();
    final cases = ref.watch(marketProvider.select((s) => s.cases));

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Community alerts'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  if (cases.isNotEmpty) ...[
                    const SectionTitle('🤝', 'Neighbour reports'),
                    for (final c in cases)
                      Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: CaseCard(c)),
                  ],
                  SectionTitle('📍', region.isEmpty ? 'In your area' : 'In $region'),
                  if (mine.isEmpty)
                    GlassCard(
                      child: Row(children: [
                        const Glyph('🌱', size: 28),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text(
                              'No outbreaks reported in your area. If you see something, report it so neighbours can prepare.',
                              style: AppTheme.callout),
                        ),
                      ]),
                    )
                  else
                    for (var i = 0; i < mine.length; i++) Reveal(index: i, child: OutbreakTile(mine[i])),
                  if (elsewhere.isNotEmpty) ...[
                    const SectionTitle('🗺️', 'Elsewhere in KwaZulu-Natal'),
                    for (var i = 0; i < elsewhere.length; i++)
                      Reveal(index: i, child: OutbreakTile(elsewhere[i], showRegion: true)),
                  ],
                  const SizedBox(height: AppTheme.s6),
                  const CommunitySection(),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
