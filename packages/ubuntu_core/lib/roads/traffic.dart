import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../live/location.dart';
import '../notify/notifier.dart';
import '../supabase/resilient.dart';
import '../supabase/supabase_boot.dart';
import 'road_models.dart' show metresBetween;

/// One live traffic incident from TomTom, kept fresh in the database every five
/// minutes. This is an outside source, so the app always names it.
class TrafficIncident {
  final String id;
  final int category; // TomTom icon category
  final int magnitude; // 0 unknown to 4 major delay
  final String description, road, fromPlace, toPlace;
  final double lat, lng;
  final int lengthM;
  final int? delaySeconds;
  final DateTime seenAt;

  const TrafficIncident({
    required this.id,
    required this.category,
    required this.magnitude,
    required this.description,
    required this.road,
    required this.fromPlace,
    required this.toPlace,
    required this.lat,
    required this.lng,
    required this.lengthM,
    required this.delaySeconds,
    required this.seenAt,
  });

  factory TrafficIncident.fromRow(Map<String, dynamic> r) => TrafficIncident(
        id: r['id'] as String,
        category: (r['category'] as num?)?.toInt() ?? 0,
        magnitude: (r['magnitude'] as num?)?.toInt() ?? 0,
        description: r['description'] as String? ?? '',
        road: r['road'] as String? ?? '',
        fromPlace: r['from_place'] as String? ?? '',
        toPlace: r['to_place'] as String? ?? '',
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lng'] as num).toDouble(),
        lengthM: (r['length_m'] as num?)?.toInt() ?? 0,
        delaySeconds: (r['delay_s'] as num?)?.toInt(),
        seenAt: DateTime.tryParse(r['seen_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get label => switch (category) {
        1 => 'Accident',
        2 => 'Fog',
        3 => 'Dangerous conditions',
        4 => 'Heavy rain',
        5 => 'Ice',
        6 => 'Heavy traffic',
        7 => 'Lane closed',
        8 => 'Road closed',
        9 => 'Roadworks',
        10 => 'Strong wind',
        11 => 'Flooding',
        14 => 'Broken down vehicle',
        _ => 'Traffic incident',
      };

  String get emoji => switch (category) {
        1 => '💥',
        2 => '🌫️',
        3 => '⚠️',
        4 => '🌧️',
        5 => '🧊',
        6 => '🚗',
        7 => '🚧',
        8 => '⛔',
        9 => '👷',
        10 => '💨',
        11 => '🌊',
        14 => '🚙',
        _ => '🚦',
      };

  /// Worth interrupting someone for.
  bool get serious => category == 1 || category == 3 || category == 8 || category == 11 || category == 14 || magnitude >= 4;

  /// Filters out the constant background of small slowdowns and short lane
  /// closures, so the list shows what matters.
  bool get worthShowing {
    switch (category) {
      case 1 || 2 || 3 || 5 || 8 || 11 || 14:
        return true;
      case 6:
        return magnitude >= 3 || (delaySeconds ?? 0) >= 600;
      case 7 || 9 || 4 || 10:
        return magnitude >= 2;
      default:
        return false;
    }
  }

  String get where {
    final parts = [if (road.isNotEmpty) road, if (fromPlace.isNotEmpty) toPlace.isEmpty || toPlace == fromPlace ? fromPlace : '$fromPlace to $toPlace'];
    return parts.join('  ·  ');
  }

  String ageText(DateTime now) {
    final m = now.difference(seenAt).inMinutes;
    if (m < 1) return 'updated just now';
    if (m < 60) return 'updated $m min ago';
    return 'updated ${m ~/ 60} h ago';
  }

  double metresFrom(double lat0, double lng0) => metresBetween(lat0, lng0, lat, lng);
}

/// Every stored incident, live. Empty when the app is running on the phone alone.
final trafficIncidentsProvider = StreamProvider<List<TrafficIncident>>((ref) {
  if (!SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('traffic_incidents').stream(primaryKey: ['id']),
    fetch: () async => [for (final r in await db.from('traffic_incidents').select()) Map<String, dynamic>.from(r)],
  ).map((rows) => [for (final r in rows) TrafficIncident.fromRow(r)]);
});

/// How far around a person counts as "near" for alerts.
const trafficRadiusKm = 25.0;

class NearIncident {
  final TrafficIncident incident;
  final double metres;
  const NearIncident(this.incident, this.metres);
}

/// Incidents that matter, within [radiusKm] of this spot, nearest first.
List<NearIncident> incidentsNear(List<TrafficIncident> all, double lat, double lng, {double radiusKm = trafficRadiusKm}) {
  final out = [
    for (final i in all)
      if (i.worthShowing)
        if (i.metresFrom(lat, lng) <= radiusKm * 1000) NearIncident(i, i.metresFrom(lat, lng))
  ]..sort((a, b) => a.metres.compareTo(b.metres));
  return out;
}

/// Serious incidents close by that this person has not been told about yet.
List<NearIncident> newSeriousNear(List<TrafficIncident> all, Set<String> told, double lat, double lng, {double radiusKm = 15}) =>
    [for (final n in incidentsNear(all, lat, lng, radiusKm: radiusKm)) if (n.incident.serious && !told.contains(n.incident.id)) n];

/// This person's incidents within [trafficRadiusKm], when their position is known.
final nearbyTrafficProvider = Provider<List<NearIncident>?>((ref) {
  final me = ref.watch(userLocationProvider).valueOrNull;
  if (me == null) return null;
  final all = ref.watch(trafficIncidentsProvider).valueOrNull ?? const [];
  return incidentsNear(all, me.$1, me.$2);
});

final _told = <String>{};

/// Tells the person about a serious incident near them, once each, while the app
/// is open. Real push alerts for a closed app need Apple and Google push set up.
final trafficWatcherProvider = Provider<void>((ref) {
  final me = ref.watch(userLocationProvider).valueOrNull;
  final all = ref.watch(trafficIncidentsProvider).valueOrNull;
  if (me == null || all == null) return;
  final fresh = newSeriousNear(all, _told, me.$1, me.$2);
  for (final n in fresh.take(2)) {
    _told.add(n.incident.id);
    final km = (n.metres / 1000).toStringAsFixed(1);
    ref.read(notifierProvider).show(
          title: '${n.incident.label} $km km away',
          body: '${n.incident.where.isEmpty ? 'On your side of town' : n.incident.where}. From TomTom traffic.',
        );
  }
});
