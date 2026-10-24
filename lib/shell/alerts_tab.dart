import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        Pill,
        WaterRadarChart,
        WaterScreen,
        forecastColor,
        forecastHeadline,
        waterProvider,
        Reveal,
        marketProvider;
import '../models/disease_info.dart';
import '../models/livestock_disease.dart';
import '../models/outbreak_report.dart';
import '../screens/map_screen.dart';
import '../services/auth_service.dart';
import '../services/outbreak_service.dart';
import '../services/region_service.dart';
import '../store/store_common.dart' show SheetFrame, timeAgo;
import '../theme/app_theme.dart';
import '../store/farm_water_section.dart';
import '../theme/glass.dart';
import '../community/community_alerts_screen.dart';
import 'alarm.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr, trn;
/// One disease in one region, however many people reported it.
class AreaOutbreak {
  final String disease;
  final String severity; // 'orange' | 'red'
  final OutbreakKind kind;
  final String region;
  final int reports;
  final DateTime? latest;
  const AreaOutbreak(this.disease, this.severity, this.kind, this.region, this.reports, this.latest);

  Color get color => severity == 'red' ? AppTheme.danger : AppTheme.warn;
  String get severityLabel => severity == 'red' ? 'Urgent' : 'Watch';
}

DateTime? _demoDate(String raw) {
  const m = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final p = raw.split(' ');
  if (p.length != 3) return null;
  final mo = m[p[1].toLowerCase().substring(0, 3)];
  final d = int.tryParse(p[0]);
  final y = int.tryParse(p[2]);
  return (mo == null || d == null || y == null) ? null : DateTime(y, mo, d);
}

String _tidy(String disease) => disease.replaceAll('_', ' ').trim();

/// Merges the demonstration sightings with live reports and groups them by
/// disease and region. Healthy scans are not outbreaks, so they are dropped.
/// Most urgent first, then most reported.
List<AreaOutbreak> buildAreaOutbreaks(List<OutbreakReport> live, {bool demo = true}) {
  final groups = <String, List<({String sev, OutbreakKind kind, DateTime? at, String region, String name})>>{};
  void add(String disease, String sev, OutbreakKind kind, DateTime? at, String region) {
    if (sev == 'green' || disease.toLowerCase().contains('healthy')) return;
    final name = _tidy(disease);
    groups
        .putIfAbsent('${name.toLowerCase()}|$region', () => [])
        .add((sev: sev, kind: kind, at: at, region: region, name: name));
  }

  if (demo) {
    for (final p in kDemoDiseasePoints) {
      add(p.disease, p.severity, OutbreakKind.plant, _demoDate(p.date), p.region);
    }
    for (final p in kDemoLivestockPoints) {
      add(p.disease, p.severity, OutbreakKind.livestock, _demoDate(p.date), p.region);
    }
  }
  for (final r in live) {
    add(r.disease, r.severity, r.kind, r.reportedAt, r.region);
  }

  final out = <AreaOutbreak>[];
  for (final g in groups.values) {
    final worst = g.any((e) => e.sev == 'red') ? 'red' : 'orange';
    DateTime? latest;
    for (final e in g) {
      if (e.at != null && (latest == null || e.at!.isAfter(latest))) latest = e.at;
    }
    out.add(AreaOutbreak(g.first.name, worst, g.first.kind, g.first.region, g.length, latest));
  }
  out.sort((a, b) {
    final s = (b.severity == 'red' ? 1 : 0) - (a.severity == 'red' ? 1 : 0);
    return s != 0 ? s : b.reports.compareTo(a.reports);
  });
  return out;
}

/// Alerts: the outbreak map up top, what is happening in the farmer's area,
/// a way to report a case, and the farm and water alerts that need action.
class AlertsTab extends ConsumerWidget {
  const AlertsTab({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = ref.watch(currentUserProvider)?.region ?? '';
    final live = ref.watch(outbreaksProvider).valueOrNull ?? const <OutbreakReport>[];
    final all = buildAreaOutbreaks(live, demo: ref.watch(marketProvider.select((s) => s.demoMode)));
    final communityCount = all.length + ref.watch(marketProvider.select((s) => s.cases.length));
    final w = ref.watch(waterProvider);
    final zone = w.myZone;
    final f = zone == null ? null : w.forecastOf(zone.id);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s4, AppTheme.s6, AppTheme.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const AlarmButton(),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Alerts', style: AppTheme.largeTitle),
                  Text(region.isEmpty ? 'Outbreaks and warnings' : 'Outbreaks near $region',
                      style: AppTheme.callout),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rCard),
                child: SizedBox(
                  height: 360,
                  child: Stack(children: [
                    const MapScreen(embedded: true),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: GestureDetector(
                        onTap: () => _push(context, const MapScreen()),
                        child: const Pill('Full screen', color: Colors.white, icon: Icons.open_in_full_rounded),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.s4),
            Reveal(
              index: 1,
              child: GlassButton(
                label: 'Report an outbreak',
                icon: Icons.flag_rounded,
                accent: AppTheme.danger,
                onPressed: () => showReportOutbreak(context, ref),
              ),
            ),
            // Water: the forecast graph, then the radar button, straight under Report.
            if (zone != null && f != null && f.days.isNotEmpty) ...[
              const SizedBox(height: AppTheme.s4),
              Reveal(
                index: 2,
                child: GlassCard(
                  onTap: () => _push(context, WaterScreen(extraSections: const [FarmWaterSection()])),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('📡', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: AppTheme.s2),
                      Expanded(child: Text('${zone.name} water, next 7 days', style: AppTheme.headline)),
                    ]),
                    const SizedBox(height: AppTheme.s1),
                    Text(forecastHeadline(f), style: AppTheme.subhead.copyWith(color: forecastColor(f), fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppTheme.s3),
                    WaterRadarChart(now: zone.level, days: f.days),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: AppTheme.s3),
            Reveal(
              index: 3,
              child: GlassButton(
                label: 'Water radar',
                icon: Icons.water_drop_rounded,
                accent: const Color(0xFF5AB8F0),
                onPressed: () => _push(context, WaterScreen(extraSections: const [FarmWaterSection()])),
              ),
            ),
            const SizedBox(height: AppTheme.s3),
            Reveal(
              index: 4,
              child: GlassButton(
                label: communityCount == 0 ? 'Community alerts' : 'Community alerts ($communityCount)',
                icon: Icons.forum_rounded,
                accent: AppTheme.livestockAccent,
                onPressed: () => _push(context, const CommunityAlertsScreen()),
              ),
            ),
            const SizedBox(height: AppTheme.s2),
            Text(
                'Community alerts are what neighbours report and discuss. Your own farm warnings are under the alarm at the top left.',
                style: AppTheme.caption),
          ]),
        ),
      ],
    );
  }
}

class OutbreakTile extends StatelessWidget {
  final AreaOutbreak o;
  final bool showRegion;
  const OutbreakTile(this.o, {this.showRegion = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s2),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
          onTap: () => showOutbreakDetails(context, o),
          child: Row(children: [
            Text(o.kind == OutbreakKind.livestock ? '🐄' : '🌿', style: const TextStyle(fontSize: 26)),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.disease, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.headline),
                Text(
                    '${showRegion ? '${o.region}  •  ' : ''}${o.reports} report${o.reports == 1 ? '' : 's'}${o.latest == null ? '' : '  •  ${timeAgo(o.latest!)}'}',
                    style: AppTheme.footnote),
              ]),
            ),
            Pill(o.severityLabel, color: o.color),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
          ]),
        ),
      );
}

// --------------------------------------------------------------- details

Future<void> showOutbreakDetails(BuildContext context, AreaOutbreak o) {
  String what;
  List<String> steps;
  String? extra;
  if (o.kind == OutbreakKind.livestock) {
    final c = LivestockDatabase.conditions.where((c) => c.name.toLowerCase() == o.disease.toLowerCase()).firstOrNull;
    what = c?.whatItIs ?? 'A livestock illness reported by farmers nearby.';
    steps = c?.actions ?? const ['Isolate sick animals', 'Call your vet or the state vet'];
    extra = c?.urgency.label;
  } else {
    final info = DiseaseDatabase.getInfo(o.disease);
    final known = info.plainName != DiseaseDatabase.getInfo('').plainName;
    what = known ? info.description : 'A crop problem reported by farmers nearby.';
    steps = known ? info.treatment : const ['Scan a leaf to see what it is', 'Remove badly affected plants'];
    extra = known ? info.severity : null;
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SheetFrame(
      title: o.disease,
      subtitle: '${o.region}  •  ${o.reports} report${o.reports == 1 ? '' : 's'}',
      children: [
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          Pill(o.severityLabel, color: o.color),
          Pill(o.kind == OutbreakKind.livestock ? 'Livestock' : 'Crop', color: AppTheme.textSecondary),
          if (extra != null) Pill(extra, color: o.color),
        ]),
        const SizedBox(height: AppTheme.s3),
        Text('What it is', style: AppTheme.headline),
        const SizedBox(height: AppTheme.s1),
        Text(what, style: AppTheme.callout),
        const SizedBox(height: AppTheme.s3),
        Text('What to do', style: AppTheme.headline),
        const SizedBox(height: AppTheme.s1),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s1),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: AppTheme.callout),
              Expanded(child: Text(s, style: AppTheme.callout)),
            ]),
          ),
        const SizedBox(height: AppTheme.s2),
        Text('Reports show an area, never a farm. Locations are rounded to about 5 km.',
            style: AppTheme.caption),
      ],
    ),
  );
}

// ---------------------------------------------------------------- report

Future<void> showReportOutbreak(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReportOutbreakSheet(),
    );

class _ReportOutbreakSheet extends ConsumerStatefulWidget {
  const _ReportOutbreakSheet();

  @override
  ConsumerState<_ReportOutbreakSheet> createState() => _ReportOutbreakSheetState();
}

class _ReportOutbreakSheetState extends ConsumerState<_ReportOutbreakSheet> {
  OutbreakKind _kind = OutbreakKind.plant;
  String? _disease;
  String _severity = 'orange';

  List<String> get _options => _kind == OutbreakKind.livestock
      ? [for (final c in LivestockDatabase.conditions) c.name]
      : [
          for (final k in DiseaseDatabase.diseases.keys)
            if (k != 'Healthy') _tidy(k)[0].toUpperCase() + _tidy(k).substring(1)
        ];

  void _send() {
    final disease = _disease;
    if (disease == null) return;
    final user = ref.read(currentUserProvider);
    final region = (user?.region.isNotEmpty ?? false) ? user!.region : 'Other';
    final centre = (RegionService.findByName(region) ?? RegionService.regions.last).center;
    ref.read(outbreakServiceProvider).report(
          disease: disease,
          severity: _severity,
          kind: _kind,
          exactLocation: RegionService.jitter(centre, '$disease${DateTime.now().microsecondsSinceEpoch}'),
          region: region,
        );
    // Also opens a neighbour-confirmation case, so other farms are alerted
    // once two of them see the same thing.
    ref.read(marketProvider.notifier).submitReport(
        disease, _kind == OutbreakKind.livestock ? '🐄' : '🌿', region);
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Reported. It is on the map now.'),
        behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return SheetFrame(
      title: 'Report an outbreak',
      subtitle: 'It shows on the map right away. Other farms get an alert once two neighbours confirm it.',
      children: [
        Row(children: [
          Expanded(
            child: _Choice('🌿 Crop', _kind == OutbreakKind.plant,
                () => setState(() {
                      _kind = OutbreakKind.plant;
                      _disease = null;
                    })),
          ),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: _Choice('🐄 Livestock', _kind == OutbreakKind.livestock,
                () => setState(() {
                      _kind = OutbreakKind.livestock;
                      _disease = null;
                    })),
          ),
        ]),
        const SizedBox(height: AppTheme.s3),
        DropdownButtonFormField<String>(
          initialValue: _disease,
          isExpanded: true,
          dropdownColor: AppTheme.sheet,
          decoration: InputDecoration(labelText: tr('What are you seeing?')),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => _disease = v),
        ),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(child: _Choice('Watch', _severity == 'orange', () => setState(() => _severity = 'orange'))),
          const SizedBox(width: AppTheme.s2),
          Expanded(child: _Choice('Urgent', _severity == 'red', () => setState(() => _severity = 'red'))),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text(
            'Your report is placed in your region, not at your farm. Pick Urgent for controlled diseases or fast spread.',
            style: AppTheme.caption),
        const SizedBox(height: AppTheme.s4),
        GlassButton(
          label: 'Send report',
          icon: Icons.send_rounded,
          onPressed: _disease == null ? null : _send,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice(this.label, this.on, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppTheme.sprout : AppTheme.glassFill,
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            border: Border.all(color: on ? AppTheme.sprout : AppTheme.glassBorder),
          ),
          child: Text(label,
              style: AppTheme.subhead.copyWith(
                  color: on ? AppTheme.onAccent : AppTheme.textPrimary,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
