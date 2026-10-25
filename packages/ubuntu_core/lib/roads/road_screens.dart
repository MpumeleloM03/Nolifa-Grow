import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart' show marketUidProvider;
import '../market/market_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../live/device_location.dart' show LocationProblem, locationProblem, openLocationFix;
import 'road_models.dart';
import 'road_store.dart';
import 'traffic.dart';

import '../tr_text.dart' show Text;
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
                      Glyph(k.emoji, size: 30),
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
          Glyph(hazard.kind.emoji, size: 30),
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

class _RoadAlertsScreenState extends ConsumerState<RoadAlertsScreen> with WidgetsBindingObserver {
  (double, double)? _me;
  bool _looked = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locate();
    // Keep the list honest while a driver is on the road.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _locate());
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the settings app is the moment the fix has just been made.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _locate();
  }

  Future<void> _locate() async {
    final p = await ref.read(reportLocationProvider)();
    if (!mounted) return;
    setState(() {
      _me = p ?? _me;
      _looked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(roadClockProvider)();
    final state = ref.watch(roadProvider);
    final live = state.live(now);
    final can = ref.watch(roadCanReportProvider);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final me = _me;
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
                      Text('Road alerts', style: AppTheme.title1),
                      const SizedBox(height: AppTheme.s1),
                      Text('Live traffic from TomTom, and warnings reported by Nolifa drivers. Each one says where it came from.', style: AppTheme.callout),
                      const SizedBox(height: AppTheme.s4),
                      if (_looked && me == null) LocationFixCard(onRetry: _locate),
                      _TrafficSection(me: me),
                      const SizedBox(height: AppTheme.s5),
                      Text('Reported by Nolifa drivers', style: AppTheme.title3),
                      const SizedBox(height: AppTheme.s1),
                      Text('Drivers report potholes, floods, crashes and roadblocks as they drive. A warning fades by itself unless another driver confirms it, and comes down when drivers say it is gone.',
                          style: AppTheme.footnote),
                      const SizedBox(height: AppTheme.s3),
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
                        GlassCard(child: Text('No Nolifa driver has reported a hazard recently. That does not mean the roads are clear: this is not a traffic report.', style: AppTheme.callout))
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

/// Live traffic from TomTom within 25 km of this person.
class _TrafficSection extends ConsumerWidget {
  final (double, double)? me;
  const _TrafficSection({required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(trafficIncidentsProvider);
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Live traffic', style: AppTheme.title3),
        const SizedBox(width: AppTheme.s2),
        Pill('TomTom', color: AppTheme.livestockAccent),
      ]),
      const SizedBox(height: AppTheme.s2),
      if (me == null)
        GlassCard(child: Text('Turn on location for Nolifa to see incidents within 25 km of you.', style: AppTheme.callout))
      else
        all.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          error: (_, __) => GlassCard(child: Text('Live traffic could not be loaded. Check your signal.', style: AppTheme.callout)),
          data: (list) {
            if (list.isEmpty) {
              return GlassCard(child: Text('No traffic data has arrived yet. It refreshes every 5 minutes.', style: AppTheme.callout));
            }
            final near = incidentsNear(list, me!.$1, me!.$2);
            if (near.isEmpty) {
              return GlassCard(child: Text('TomTom shows no serious incidents within 25 km of you right now.', style: AppTheme.callout));
            }
            return Column(children: [
              for (final n in near.take(25))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s2),
                  child: GlassCard(
                    padding: const EdgeInsets.all(AppTheme.s4),
                    child: Row(children: [
                      Glyph(n.incident.emoji, size: 28),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${n.incident.label}${n.incident.description.isNotEmpty && n.incident.description.toLowerCase() != n.incident.label.toLowerCase() ? '  ·  ${n.incident.description}' : ''}', style: AppTheme.headline),
                          if (n.incident.where.isNotEmpty) Text(n.incident.where, style: AppTheme.footnote),
                          Text(
                              '${n.metres < 1000 ? '${n.metres.round()} m' : '${(n.metres / 1000).toStringAsFixed(1)} km'} away  ·  TomTom  ·  ${n.incident.ageText(now)}',
                              style: AppTheme.caption),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
    ]);
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
    final near = ref.watch(nearbyTrafficProvider);
    final serious = near?.where((n) => n.incident.serious).length ?? 0;
    return GlassCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadAlertsScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Glyph('🚧', size: 28),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Road alerts', style: AppTheme.headline),
              Text(
                  [
                    if (near != null) near.isEmpty ? 'No traffic incidents within 25 km' : '${near.length} traffic ${near.length == 1 ? 'incident' : 'incidents'} within 25 km${serious > 0 ? ' ($serious serious)' : ''}',
                    live.isEmpty ? 'none reported by drivers' : '${live.length} from drivers',
                  ].join('  ·  '),
                  style: AppTheme.footnote),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
        if (live.isNotEmpty) ...[
          const SizedBox(height: AppTheme.s2),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in {for (final h in live) h.kind})
              Pill('${live.where((h) => h.kind == k).length}', color: AppTheme.livestockAccent),
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

/// Says why the phone has no position and opens the setting that fixes it.
class LocationFixCard extends StatelessWidget {
  final VoidCallback onRetry;
  const LocationFixCard({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LocationProblem?>(
      valueListenable: locationProblem,
      builder: (context, why, _) {
        final text = switch (why) {
          LocationProblem.servicesOff => 'Location is switched off on this phone. Alerts near you and job tracking need it.',
          LocationProblem.denied => 'Nolifa is not allowed to use your location yet. Allow it to see alerts near you.',
          LocationProblem.deniedForever => 'Location was blocked for Nolifa. Open settings and allow it while using the app.',
          _ => 'Nolifa could not find your position. Move to open sky or check your signal, then try again.',
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s4),
          child: GlassCard(
            tint: AppTheme.warn.withValues(alpha: 0.12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.location_off_rounded, color: AppTheme.warn),
                const SizedBox(width: AppTheme.s2),
                Expanded(child: Text('We cannot see where you are', style: AppTheme.headline)),
              ]),
              const SizedBox(height: AppTheme.s2),
              Text(text, style: AppTheme.callout),
              const SizedBox(height: AppTheme.s3),
              Row(children: [
                if (why != LocationProblem.unavailable && why != null)
                  Expanded(
                    child: GlassButton(
                      label: 'Open settings',
                      icon: Icons.settings_rounded,
                      onPressed: () async {
                        await openLocationFix();
                      },
                    ),
                  ),
                if (why != LocationProblem.unavailable && why != null) const SizedBox(width: AppTheme.s2),
                Expanded(child: GhostButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry)),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
