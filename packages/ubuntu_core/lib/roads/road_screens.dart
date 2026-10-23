import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart' show marketUidProvider;
import '../market/market_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'road_models.dart';
import 'road_store.dart';

/// Where the driver is right now as (latitude, longitude), or null when
/// location is off or refused. The driver app supplies the real GPS reading.
final reportLocationProvider =
    Provider<Future<(double, double)?> Function()>((ref) => () async => null);

/// Asks which hazard it is, then reports it where the driver is. Like Waze:
/// one tap on the icon, no typing while moving.
Future<void> showRoadReportSheet(BuildContext context, WidgetRef ref) async {
  final kind = await showModalBottomSheet<HazardKind>(
    context: context,
    backgroundColor: AppTheme.sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s5),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What is on the road?', style: AppTheme.title3),
          const SizedBox(height: 2),
          Text('Other drivers on this road are warned straight away.', style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s4),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppTheme.s2,
            crossAxisSpacing: AppTheme.s2,
            childAspectRatio: 0.82,
            children: [
              for (final k in HazardKind.values)
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.rControl),
                  onTap: () => Navigator.pop(sheet, k),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.glassFill,
                      borderRadius: BorderRadius.circular(AppTheme.rControl),
                      border: Border.all(color: AppTheme.glassBorder),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(k.emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(k.label, textAlign: TextAlign.center, style: AppTheme.caption, maxLines: 2),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  HapticFeedback.mediumImpact();
  final where = await ref.read(reportLocationProvider)();
  if (!context.mounted) return;
  late final String message;
  if (where == null) {
    message = ('Turn location on so we can place the warning.');
  } else {
    final out = await ref.read(roadProvider.notifier).report(kind, where.$1, where.$2);
    message = switch (out) {
      ReportOutcome.created => ('${kind.label} reported. Drivers nearby are warned.'),
      ReportOutcome.merged => ('Someone already reported this one. We counted you as another sighting.'),
      ReportOutcome.notAllowed => ('Only verified drivers can report. Finish your checks first.'),
    };
  }
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// One warning, with the two buttons that keep the map honest.
class HazardTile extends ConsumerWidget {
  final RoadHazard hazard;
  final double? metresAway;
  const HazardTile(this.hazard, {super.key, this.metresAway});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(roadClockProvider)();
    final can = ref.watch(roadCanReportProvider);
    final uid = ref.watch(marketUidProvider);
    final mine = hazard.confirms.contains(uid) || hazard.denies.contains(uid);
    final away = metresAway;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(hazard.kind.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hazard.kind.label, style: AppTheme.headline),
              Text(
                  '${hazard.ageText(now)}  -  ${hazard.confirms.length} ${hazard.confirms.length == 1 ? 'driver' : 'drivers'} saw it'
                  '${away == null ? '' : '  -  ${away < 1000 ? '${away.round()} m' : '${(away / 1000).toStringAsFixed(1)} km'} away'}',
                  style: AppTheme.footnote),
            ]),
          ),
          if (hazard.demo) Pill('Sample', color: AppTheme.warn),
        ]),
        if (hazard.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(hazard.note, style: AppTheme.callout)),
        Padding(padding: const EdgeInsets.only(top: AppTheme.s1), child: Text(hazard.kind.advice, style: AppTheme.footnote)),
        if (can)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s3),
            child: Row(children: [
              Expanded(
                child: GhostButton(
                  label: 'Still there',
                  icon: Icons.check_rounded,
                  onPressed: mine && hazard.confirms.contains(uid) ? null : () => ref.read(roadProvider.notifier).confirm(hazard.id),
                ),
              ),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                child: GhostButton(
                  label: 'Gone',
                  icon: Icons.close_rounded,
                  onPressed: hazard.denies.contains(uid) ? null : () => ref.read(roadProvider.notifier).deny(hazard.id),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Every live warning, nearest first when the driver's position is known.
class RoadAlertsScreen extends ConsumerStatefulWidget {
  const RoadAlertsScreen({super.key});

  @override
  ConsumerState<RoadAlertsScreen> createState() => _RoadAlertsScreenState();
}

class _RoadAlertsScreenState extends ConsumerState<RoadAlertsScreen> {
  late final Future<(double, double)?> _where = ref.read(reportLocationProvider)();

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(roadClockProvider)();
    final state = ref.watch(roadProvider);
    final live = state.live(now);
    final can = ref.watch(roadCanReportProvider);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: FutureBuilder<(double, double)?>(
            future: _where,
            builder: (context, snap) {
              final me = snap.data;
              double? away(RoadHazard h) => me == null ? null : metresBetween(me.$1, me.$2, h.lat, h.lng);
              final list = [...live];
              if (me != null) list.sort((a, b) => away(a)!.compareTo(away(b)!));
              return CustomScrollView(
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
                    title: const Text('Road alerts'),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                    sliver: SliverList.list(children: [
                      Text('Warnings from drivers', style: AppTheme.title1),
                      const SizedBox(height: AppTheme.s1),
                      Text(
                          'Drivers report potholes, floods, crashes and roadblocks as they drive. A warning fades by itself unless another driver confirms it, and comes down when drivers say it is gone.',
                          style: AppTheme.callout),
                      const SizedBox(height: AppTheme.s4),
                      GlassButton(
                        label: can ? 'Report a hazard' : 'Verify to report',
                        icon: Icons.add_alert_rounded,
                        accent: AppTheme.livestockAccent,
                        onPressed: can ? () => showRoadReportSheet(context, ref) : null,
                      ),
                      if (!state.shared)
                        Padding(
                          padding: const EdgeInsets.only(top: AppTheme.s3),
                          child: Text('Prototype: warnings stay on this phone until the shared database is connected. Samples are marked.',
                              style: AppTheme.footnote),
                        ),
                      const SizedBox(height: AppTheme.s4),
                      if (list.isEmpty)
                        GlassCard(child: Text('No live warnings right now. Roads look clear.', style: AppTheme.callout))
                      else
                        for (final h in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s3),
                            child: HazardTile(h, metresAway: away(h)),
                          ),
                    ]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A short card for the Jobs page: how many warnings are live and one tap to
/// report or read them.
class RoadAlertsCard extends ConsumerWidget {
  const RoadAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(roadClockProvider)();
    final live = ref.watch(roadProvider).live(now);
    final can = ref.watch(roadCanReportProvider);
    return GlassCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadAlertsScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🚧', style: TextStyle(fontSize: 28)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Road alerts', style: AppTheme.headline),
              Text(live.isEmpty ? 'No live warnings' : '${live.length} live ${live.length == 1 ? 'warning' : 'warnings'} from drivers', style: AppTheme.footnote),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
        if (live.isNotEmpty) ...[
          const SizedBox(height: AppTheme.s2),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in {for (final h in live) h.kind})
              Pill('${k.emoji} ${live.where((h) => h.kind == k).length}', color: AppTheme.livestockAccent),
          ]),
        ],
        if (can) ...[
          const SizedBox(height: AppTheme.s3),
          GhostButton(label: 'Report a hazard', icon: Icons.add_alert_rounded, onPressed: () => showRoadReportSheet(context, ref)),
        ],
      ]),
    );
  }
}
