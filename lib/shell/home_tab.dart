import '../members/vet_screens.dart';
import '../care/care_screen.dart';
import '../care/care_store.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Reveal;
import '../models/cattle.dart';
import '../models/diagnosis_record.dart';
import '../models/disease_info.dart';
import '../crops/my_crops_screen.dart';
import '../water/supplier_screen.dart';
import '../weather/weather_card.dart';
import '../screens/history_screen.dart';
import '../screens/livestock/herd_screen.dart';
import '../screens/livestock/symptom_checker_screen.dart';
import '../services/auth_service.dart';
import '../services/cattle_service.dart';
import '../services/crop_scan.dart';
import '../services/history_service.dart';
import '../store/store_common.dart' show timeAgo;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/language_toggle.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// The Diagnose tab: check a sick plant or animal. Farmers also get their crop
/// tracker, herd, vets and herd care; community members get the free checks.
/// Water and the outbreak map have their own tabs, so they are not repeated here.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  late Future<List<DiagnosisRecord>> _history = HistoryService().getHistory();

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _scan() async {
    HapticFeedback.mediumImpact();
    await startCropScan(context, ref);
    if (mounted) setState(() => _history = HistoryService().getHistory());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final name = (user?.name.trim().isNotEmpty ?? false) ? user!.name.trim().split(' ').first : 'there';
    final community = user?.isCommunity ?? false;
    final herd = ref.watch(herdProvider);
    final head = herd.valueOrNull?.where((c) => c.status == CattleStatus.active).length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sawubona, $name', style: AppTheme.largeTitle),
                  const SizedBox(height: AppTheme.s1),
                  Text(community ? 'Check a sick plant or animal in seconds' : 'Protect your farm and your community',
                      style: AppTheme.callout),
                ]),
              ),
              const LanguageToggle(),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            // Recent scans first and compact: the thing a farmer checks most.
            FutureBuilder<List<DiagnosisRecord>>(
              future: _history,
              builder: (_, snap) {
                final list = (snap.data ?? const <DiagnosisRecord>[]).take(2).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Recent scans', style: AppTheme.headline),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _push(const HistoryScreen()),
                      child: Text('See all', style: AppTheme.footnote.copyWith(color: AppTheme.sprout)),
                    ),
                  ]),
                  const SizedBox(height: AppTheme.s2),
                  if (list.isEmpty)
                    Text('Your scans will show up here.', style: AppTheme.footnote)
                  else
                    for (final r in list) _ScanRow(r),
                ]);
              },
            ),
            if (community || (user?.growsCrops ?? true)) ...[
            const SizedBox(height: AppTheme.s4),
            Reveal(
              child: _ScanCard(
                emoji: '🌿',
                title: community ? 'Check a sick plant' : 'Scan a crop',
                line: 'Photograph a leaf. Get the disease and what to do, even with no signal.',
                action: 'Open camera',
                icon: Icons.camera_alt_rounded,
                accent: AppTheme.plantAccent,
                onTap: _scan,
                second: community ? null : GlassButton(
                  label: 'Crop health AI: my crops',
                  icon: Icons.insights_rounded,
                  accent: const Color(0xFF8FE3C6),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _push(const MyCropsScreen());
                  },
                ),
              ),
            ),
            ],
            if (community || (user?.keepsLivestock ?? true)) ...[
            const SizedBox(height: AppTheme.s4),
            Reveal(
              index: 1,
              child: community
                  ? _ScanCard(
                      emoji: '🐄',
                      title: 'Check a sick animal',
                      line: 'Tick the signs you see. Controlled diseases like foot-and-mouth are flagged first, with who to call.',
                      action: 'Check symptoms',
                      icon: Icons.checklist_rounded,
                      accent: AppTheme.livestockAccent,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _push(const SymptomCheckerScreen());
                      },
                    )
                  : _ScanCard(
                emoji: '🐄',
                title: 'Sick animal? Ask a vet',
                line: 'Film it, and one of our vets will watch it, say what they think it is and why, and tell you what to do. Words alone cannot tell a vet what is wrong.',
                action: 'Send a video to a vet',
                icon: Icons.videocam_rounded,
                accent: AppTheme.livestockAccent,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _push(const VetHomeScreen());
                },
                second: GlassButton(
                  label: head == null ? 'Your herd' : 'Your herd ($head head)',
                  icon: Icons.pets_rounded,
                  accent: const Color(0xFFF2C77B),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _push(const HerdScreen());
                  },
                ),
              ),
            ),
            ],
            if (!community) ...[
              const SizedBox(height: AppTheme.s4),
              Reveal(index: 2, child: _CareCard(onOpen: () => _push(const CareScreen()))),
            ],
            const SizedBox(height: AppTheme.s3),
            const Reveal(index: 3, child: WeatherCard()),
            if (!community) ...[
            const SizedBox(height: AppTheme.s3),
            Reveal(
              index: 4,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                onTap: () => _push(const WaterSupplierScreen()),
                child: Row(children: [
                  const Glyph('🚰', size: 26),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Water provider', style: AppTheme.headline),
                      Text('Got a borehole or tanker? Help a community in need.', style: AppTheme.footnote),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                ]),
              ),
            ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  final String emoji, title, line, action;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final Widget? second;
  const _ScanCard({
    required this.emoji,
    required this.title,
    required this.line,
    required this.action,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.second,
  });

  @override
  Widget build(BuildContext context) => GlassCard(
        tint: accent.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(AppTheme.s5),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Glyph(emoji, size: 44),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text(title, style: AppTheme.title2)),
          ]),
          const SizedBox(height: AppTheme.s2),
          Text(line, style: AppTheme.callout),
          const SizedBox(height: AppTheme.s4),
          GlassButton(label: action, icon: icon, accent: accent, onPressed: onTap),
          if (second != null) ...[const SizedBox(height: AppTheme.s2), second!],
        ]),
      );
}

class _ScanRow extends StatelessWidget {
  final DiagnosisRecord r;
  const _ScanRow(this.r);

  @override
  Widget build(BuildContext context) {
    final info = DiseaseDatabase.getInfo(r.label);
    final color = switch (info.severityColor) {
      'red' => AppTheme.danger,
      'orange' => AppTheme.warn,
      _ => AppTheme.ok,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s2),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s3, vertical: AppTheme.s2),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.plainName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
              Text(timeAgo(r.date), style: AppTheme.caption),
            ]),
          ),
          Text('${r.confidence}%', style: AppTheme.caption),
        ]),
      ),
    );
  }
}


/// Today's herd care at a glance: the next water and feed, and vaccines to
/// answer. Only shows once the farm has animals on the register.
class _CareCard extends ConsumerWidget {
  final VoidCallback onOpen;
  const _CareCard({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sum = ref.watch(vaccineSummaryProvider);
    if (sum == null || sum.total == 0) return const SizedBox.shrink();
    final care = ref.watch(careProvider);
    final store = ref.read(careProvider.notifier);
    final now = TimeOfDay.now();
    int mins(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final open = <(String, String)>[
      for (final t in care.settings.waterTimes) if (!store.done('water', t)) ('water', t),
      for (final t in care.settings.feedTimes) if (!store.done('feed', t)) ('feed', t),
    ]..sort((a, b) => mins(a.$2).compareTo(mins(b.$2)));
    final nowM = now.hour * 60 + now.minute;
    final overdue = [for (final o in open) if (mins(o.$2) <= nowM) o];
    final next = open.where((o) => mins(o.$2) > nowM).firstOrNull;

    String line;
    if (overdue.isNotEmpty) {
      final o = overdue.first;
      line = '${o.$1 == 'water' ? 'Water' : 'Feed'} at ${o.$2} is not ticked off yet.';
    } else if (next != null) {
      line = 'Next: ${next.$1 == 'water' ? 'water' : 'feed'} at ${next.$2}.';
    } else {
      line = 'Everything for today is done.';
    }
    final vax = sum.needAttention == 0
        ? 'All ${sum.total} animals have a vaccine record.'
        : '${sum.needAttention} of ${sum.total} animals need a vaccine answer or booster.';
    return GlassCard(
      tint: (overdue.isNotEmpty || sum.needAttention > 0 ? AppTheme.warn : AppTheme.ok).withValues(alpha: 0.10),
      padding: const EdgeInsets.all(AppTheme.s5),
      onTap: onOpen,
      child: Row(children: [
        const Glyph('🗓️', size: 38),
        const SizedBox(width: AppTheme.s4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Herd care today', style: AppTheme.title3),
            const SizedBox(height: AppTheme.s1),
            Text(line, style: AppTheme.callout),
            Text(vax, style: AppTheme.footnote),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
      ]),
    );
  }
}
