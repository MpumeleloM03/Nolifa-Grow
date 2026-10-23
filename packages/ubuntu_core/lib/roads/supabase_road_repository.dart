import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_boot.dart';
import 'road_models.dart';
import 'road_repository.dart';

/// Road warnings shared between drivers in `road_hazards`. Only warnings
/// still inside their lifetime are listened to, so old ones cost nothing.
class SupabaseRoadRepository implements RoadRepository {
  SupabaseRoadRepository({SupabaseClient? db, DateTime Function()? clock})
      : _db = db ?? SupabaseBoot.client,
        _clock = clock ?? DateTime.now;

  final SupabaseClient _db;
  final DateTime Function() _clock;

  @override
  bool get shared => true;

  @override
  Stream<List<RoadHazard>> watch() {
    // The longest-lived kind is 72 hours, so nothing older can be valid.
    final since = _clock().subtract(const Duration(hours: 72)).millisecondsSinceEpoch;
    return _db.from('road_hazards').stream(primaryKey: ['id']).gt('last_seen', since).map((rows) => [
          for (final r in rows) RoadHazard.fromJson({...Map<String, dynamic>.from(r['data'] as Map), 'id': r['id']}),
        ]);
  }

  @override
  Future<void> save(RoadHazard h) => _db.rpc('save_hazard', params: {
        'p_id': h.id,
        'p_data': {
          'kind': h.kind.name,
          'lat': h.lat,
          'lng': h.lng,
          'reportedAt': h.reportedAt.millisecondsSinceEpoch,
          'lastSeen': h.lastSeen.millisecondsSinceEpoch,
          'reporter': h.reporter,
          'reporterName': h.reporterName,
          'confirms': h.confirms,
          'denies': h.denies,
          'note': h.note,
        },
      });
}
