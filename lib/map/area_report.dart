import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/disease_info.dart';
import '../models/livestock_disease.dart';
import '../models/outbreak_report.dart';
import '../outbreak/outbreak_trust.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show ReportCase;
import '../screens/map_screen.dart' show DiseasePoint, kDemoDiseasePoints, kDemoLivestockPoints;
import 'hex_grid.dart';

/// One sighting on the map, from the demonstration data or a real report.
class Sighting {
  final String disease;
  final OutbreakKind kind;
  final String severity; // 'green' | 'orange' | 'red'
  final DateTime at;
  final String region;
  final double lat;
  final double lng;
  final Trust trust;
  final String? caseId;
  const Sighting(this.disease, this.kind, this.severity, this.at, this.region, this.lat, this.lng,
      {this.trust = Trust.confirmed, this.caseId});

  /// How hard this sighting heats its hexagon: urgent counts most, and old
  /// reports fade over six weeks so a finished outbreak stops glowing.
  /// Unconfirmed reports do not heat the map; they show as their own marker.
  double weight(DateTime now) {
    if (!trust.alerts) return 0;
    final base = switch (severity) { 'red' => 1.0, 'orange' => 0.6, _ => 0.0 };
    final age = now.difference(at).inDays;
    return base * (1 - age / 42).clamp(0.15, 1.0);
  }
}

String tidyName(String d) => d.replaceAll('_', ' ').trim();

/// What is affecting one disease in one hexagon, and how it is being handled.
class AreaProblem {
  final String disease;
  final OutbreakKind kind;
  final String severity;
  final int reports;
  final DateTime latest;
  final List<String> response;
  final Trust trust;
  final String? caseId;
  const AreaProblem(this.disease, this.kind, this.severity, this.reports, this.latest, this.response,
      {this.trust = Trust.confirmed, this.caseId});
}

class HexCell {
  final HexId id;
  final List<Sighting> sightings;
  final double heat;
  const HexCell(this.id, this.sightings, this.heat);

  bool get isEmpty => sightings.isEmpty;

  /// The strongest trust among this hexagon's own reports, or null if none.
  Trust? get trust {
    Trust? best;
    for (final s in sightings) {
      if (best == null || s.trust.index > best.index) best = s.trust;
    }
    return best;
  }
}

/// Demonstration sightings, dated relative to today so the map is never stale.
List<Sighting> demoSightings(DateTime now) {
  final newest = DateTime(2026, 5, 28);
  DateTime shift(String raw) {
    final d = _parse(raw) ?? newest;
    return now.subtract(Duration(days: math.max(0, newest.difference(d).inDays) + 1));
  }

  // Each demo sighting stands for a cluster, so the map reads as a heat map
  // with hot cores and cooler edges rather than a few isolated dots.
  final out = <Sighting>[];
  void spread(DiseasePoint p, OutbreakKind kind) {
    final seed = p.disease.hashCode ^ p.location.latitude.hashCode ^ p.location.longitude.hashCode;
    final r = math.Random(seed);
    final trust = p.severity == 'red' ? Trust.verified : Trust.confirmed;
    out.add(Sighting(tidyName(p.disease), kind, p.severity, shift(p.date), p.region, p.location.latitude, p.location.longitude,
        trust: trust));
    for (var i = 0; i < 9; i++) {
      // Closer to the centre is more likely: square the random radius.
      final d = math.pow(r.nextDouble(), 1.6) * 0.32;
      final a = r.nextDouble() * 2 * math.pi;
      out.add(Sighting(tidyName(p.disease), kind, i % 3 == 0 ? 'red' : p.severity, shift(p.date), p.region,
          p.location.latitude + d * math.sin(a), p.location.longitude + d * math.cos(a), trust: trust));
    }
  }

  for (final p in kDemoDiseasePoints) {
    spread(p, OutbreakKind.plant);
  }
  for (final p in kDemoLivestockPoints) {
    spread(p, OutbreakKind.livestock);
  }
  return out;
}

DateTime? _parse(String raw) {
  const m = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};
  final p = raw.split(' ');
  if (p.length != 3) return null;
  final mo = m[p[1].toLowerCase().substring(0, 3)];
  final d = int.tryParse(p[0]);
  final y = int.tryParse(p[2]);
  return (mo == null || d == null || y == null) ? null : DateTime(y, mo, d);
}

/// Real reports, each carrying how far its case has got. Rejected ones leave
/// the map.
List<Sighting> liveSightings(List<OutbreakReport> live, [Map<String, ReportCase> cases = const {}]) => [
      for (final r in live)
        if (trustOfCase(r.caseId == null ? null : cases[r.caseId]) case final t?)
          Sighting(tidyName(r.disease), r.kind, r.severity, r.reportedAt, r.region, r.location.latitude,
              r.location.longitude,
              trust: t, caseId: r.caseId)
    ];

/// Groups sightings into hexagons and works out each one's heat.
Map<HexId, HexCell> buildCells(HexGrid grid, Iterable<Sighting> all, DateTime now, {OutbreakKind? only}) {
  final by = <HexId, List<Sighting>>{};
  for (final s in all) {
    if (only != null && s.kind != only) continue;
    if (s.severity == 'green' || s.disease.toLowerCase().contains('healthy')) continue;
    by.putIfAbsent(grid.cellOf(LatLng(s.lat, s.lng)), () => []).add(s);
  }
  // Heat spreads a little to the ring of hexagons around each one, so busy
  // areas glow out into their surroundings the way a heat map should.
  final heat = <HexId, double>{};
  for (final e in by.entries) {
    final own = e.value.fold(0.0, (a, s) => a + s.weight(now));
    heat[e.key] = (heat[e.key] ?? 0) + own;
    for (final n in e.key.neighbours) {
      heat[n] = (heat[n] ?? 0) + own * 0.35;
    }
  }
  return {
    for (final e in heat.entries) e.key: HexCell(e.key, by[e.key] ?? const [], e.value)
  };
}

/// Groups a cell's sightings by disease, worst and most reported first.
List<AreaProblem> problemsIn(HexCell cell) {
  final g = <String, List<Sighting>>{};
  for (final s in cell.sightings) {
    g.putIfAbsent('${s.kind.name}|${s.disease.toLowerCase()}', () => []).add(s);
  }
  final out = <AreaProblem>[];
  for (final list in g.values) {
    final worst = list.any((s) => s.severity == 'red') ? 'red' : 'orange';
    final latest = list.map((s) => s.at).reduce((a, b) => a.isAfter(b) ? a : b);
    // The best-backed report speaks for the group; its case gets the buttons.
    final lead = list.reduce((a, b) => b.trust.index > a.trust.index ? b : a);
    final withCase = list.where((s) => s.caseId != null && s.trust == lead.trust).firstOrNull;
    out.add(AreaProblem(list.first.disease, list.first.kind, worst, list.length, latest,
        responseTo(list.first.disease, list.first.kind, worst),
        trust: lead.trust, caseId: withCase?.caseId));
  }
  out.sort((a, b) {
    final t = b.trust.index - a.trust.index;
    if (t != 0) return t;
    final s = (b.severity == 'red' ? 1 : 0) - (a.severity == 'red' ? 1 : 0);
    return s != 0 ? s : b.reports.compareTo(a.reports);
  });
  return out;
}

/// How an outbreak is normally dealt with, in plain steps.
List<String> responseTo(String disease, OutbreakKind kind, String severity) {
  if (kind == OutbreakKind.livestock) {
    final c = LivestockDatabase.conditions
        .where((c) => c.name.toLowerCase() == disease.toLowerCase())
        .firstOrNull;
    if (c == null) return const ['Isolate sick animals', 'Call your vet'];
    return [
      if (c.urgency == Urgency.notifiable) 'Reported to the state veterinarian, who controls animal movement',
      ...c.actions.take(3),
    ];
  }
  final info = DiseaseDatabase.getInfo(disease);
  final known = info.plainName != DiseaseDatabase.getInfo('').plainName;
  return known
      ? [info.severity, ...info.treatment.take(2)]
      : ['Scan a leaf to see what it is', 'Remove badly affected plants'];
}
