import 'dart:math' as math;

/// What a driver can warn others about, in the order the report sheet shows them.
enum HazardKind {
  pothole('Pothole', '🕳️', 'Slow down, bad surface', 72 * 60),
  flooding('Flooding', '🌊', 'Water on the road, do not cross if you cannot see the road', 6 * 60),
  accident('Accident', '💥', 'Crash ahead, expect delays', 2 * 60),
  roadworks('Roadworks', '🚧', 'Lane closed or one-way stop and go', 24 * 60),
  blocked('Road blocked', '⛔', 'Road closed, find another way', 3 * 60),
  police('Police / roadblock', '👮', 'Roadblock or checkpoint ahead', 90),
  outage('Traffic lights out', '🚦', 'Power is off, treat it as a four-way stop', 4 * 60),
  animals('Animals on road', '🐄', 'Cattle or goats on the road', 60);

  final String label;
  final String emoji;
  final String advice;

  /// How long a report stays valid without another driver seeing it again.
  final int lifeMinutes;
  const HazardKind(this.label, this.emoji, this.advice, this.lifeMinutes);

  static HazardKind parse(String? raw) =>
      HazardKind.values.firstWhere((k) => k.name == raw, orElse: () => HazardKind.pothole);
}

/// One warning on one spot. [confirms] always includes the reporter.
class RoadHazard {
  final String id;
  final HazardKind kind;
  final double lat;
  final double lng;
  final DateTime reportedAt;
  final DateTime lastSeen;
  final String reporter;
  final String reporterName;
  final List<String> confirms;
  final List<String> denies;
  final String note;

  /// True for the sample warnings that ship with the demo.
  final bool demo;

  const RoadHazard({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.reportedAt,
    required this.lastSeen,
    required this.reporter,
    this.reporterName = 'Driver',
    this.confirms = const [],
    this.denies = const [],
    this.note = '',
    this.demo = false,
  });

  DateTime get expiresAt => lastSeen.add(Duration(minutes: kind.lifeMinutes));

  /// Two or more drivers saying "not there" and more of them than say "there"
  /// takes it down before its time.
  bool get disproved => denies.length >= 2 && denies.length > confirms.length;

  bool activeAt(DateTime now) => now.isBefore(expiresAt) && !disproved;

  RoadHazard seenBy(String uid, DateTime now) => RoadHazard(
        id: id,
        kind: kind,
        lat: lat,
        lng: lng,
        reportedAt: reportedAt,
        lastSeen: now,
        reporter: reporter,
        reporterName: reporterName,
        confirms: confirms.contains(uid) ? confirms : [...confirms, uid],
        denies: [for (final d in denies) if (d != uid) d],
        note: note,
        demo: demo,
      );

  RoadHazard notThere(String uid) => RoadHazard(
        id: id,
        kind: kind,
        lat: lat,
        lng: lng,
        reportedAt: reportedAt,
        lastSeen: lastSeen,
        reporter: reporter,
        reporterName: reporterName,
        confirms: [for (final c in confirms) if (c != uid || c == reporter) c],
        denies: denies.contains(uid) ? denies : [...denies, uid],
        note: note,
        demo: demo,
      );

  String ageText(DateTime now) {
    final m = now.difference(lastSeen).inMinutes;
    if (m < 2) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'lat': lat,
        'lng': lng,
        'reportedAt': reportedAt.millisecondsSinceEpoch,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'reporter': reporter,
        'reporterName': reporterName,
        'confirms': confirms,
        'denies': denies,
        'note': note,
        'demo': demo,
      };

  factory RoadHazard.fromJson(Map<String, dynamic> m) => RoadHazard(
        id: m['id'] as String,
        kind: HazardKind.parse(m['kind'] as String?),
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        reportedAt: DateTime.fromMillisecondsSinceEpoch((m['reportedAt'] as num).toInt()),
        lastSeen: DateTime.fromMillisecondsSinceEpoch((m['lastSeen'] as num).toInt()),
        reporter: m['reporter'] as String? ?? '',
        reporterName: m['reporterName'] as String? ?? 'Driver',
        confirms: [for (final c in (m['confirms'] as List? ?? const [])) c as String],
        denies: [for (final c in (m['denies'] as List? ?? const [])) c as String],
        note: m['note'] as String? ?? '',
        demo: m['demo'] as bool? ?? false,
      );
}

// ------------------------------------------------------------ geometry

const _earthM = 6371000.0;

/// Great-circle distance in metres.
double metresBetween(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// A warning on the driver's route, with how far along it is.
class HazardAhead {
  final RoadHazard hazard;
  final double metresAhead;
  const HazardAhead(this.hazard, this.metresAhead);

  String get distanceText => metresAhead < 50
      ? 'a moment'
      : metresAhead < 1000
          ? '${(metresAhead / 50).round() * 50} m'
          : '${(metresAhead / 1000).toStringAsFixed(1)} km';
}

/// Which warnings sit on [route] (a list of lat/lng pairs) in front of the
/// driver at [me]. A warning counts when it is within [offRouteM] of the line
/// and further along it than the driver. Sorted nearest first.
List<HazardAhead> hazardsAhead(
  List<(double, double)> route,
  (double, double) me,
  Iterable<RoadHazard> hazards, {
  double offRouteM = 120,
  double horizonM = 15000,
}) {
  if (route.length < 2) return const [];
  final cum = <double>[0];
  for (var i = 1; i < route.length; i++) {
    cum.add(cum.last + metresBetween(route[i - 1].$1, route[i - 1].$2, route[i].$1, route[i].$2));
  }
  int nearest((double, double) p, {double? within}) {
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = metresBetween(p.$1, p.$2, route[i].$1, route[i].$2);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  final meIdx = nearest(me);
  final out = <HazardAhead>[];
  for (final h in hazards) {
    // The route is drawn between road vertices, so test the segment as well as the points.
    var bestD = double.infinity;
    var bestAlong = 0.0;
    for (var i = 0; i < route.length; i++) {
      final d = metresBetween(h.lat, h.lng, route[i].$1, route[i].$2);
      if (d < bestD) {
        bestD = d;
        bestAlong = cum[i];
      }
    }
    if (bestD > offRouteM) continue;
    final ahead = bestAlong - cum[meIdx];
    if (ahead < -20 || ahead > horizonM) continue;
    out.add(HazardAhead(h, math.max(0, ahead)));
  }
  out.sort((a, b) => a.metresAhead.compareTo(b.metresAhead));
  return out;
}
