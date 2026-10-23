import 'package:cloud_firestore/cloud_firestore.dart';
import 'road_models.dart';
import 'road_repository.dart';

/// Road warnings shared between drivers in `roadHazards/{id}`. Only warnings
/// still inside their lifetime are listened to, so old ones cost nothing.
class FirestoreRoadRepository implements RoadRepository {
  FirestoreRoadRepository({FirebaseFirestore? db, DateTime Function()? clock})
      : _db = db ?? FirebaseFirestore.instance,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('roadHazards');

  @override
  bool get shared => true;

  @override
  Stream<List<RoadHazard>> watch() {
    // The longest-lived kind is 72 hours, so nothing older can be valid.
    final since = _clock().subtract(const Duration(hours: 72)).millisecondsSinceEpoch;
    return _col.where('lastSeen', isGreaterThan: since).snapshots().map((q) => [
          for (final d in q.docs) RoadHazard.fromJson({...d.data(), 'id': d.id}),
        ]);
  }

  @override
  Future<void> save(RoadHazard h) => _col.doc(h.id).set({
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
      });
}
