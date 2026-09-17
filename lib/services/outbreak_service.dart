import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/outbreak_report.dart';
import 'firebase_boot.dart';

/// Community disease sightings, stored flat at outbreaks/.
///
/// Readable by every signed-in farmer — the whole point is that your
/// neighbour's report warns you before the disease reaches your fence.
class OutbreakService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('outbreaks');

  Stream<List<OutbreakReport>> watchRecent({int days = 60}) {
    if (!FirebaseBoot.ready) return Stream.value(const []);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _col
        .where('reportedAt', isGreaterThan: Timestamp.fromDate(cutoff))
        .snapshots()
        .map((s) => s.docs.map(OutbreakReport.fromDoc).toList());
  }

  Future<void> report({
    required String disease,
    required String severity,
    required OutbreakKind kind,
    required LatLng exactLocation,
    required String region,
  }) {
    if (!FirebaseBoot.ready) return Future.value();
    return _col.add(
      OutbreakReport(
        id: '',
        disease: disease,
        severity: severity,
        kind: kind,
        location: OutbreakReport.coarsen(exactLocation),
        region: region,
        reportedAt: DateTime.now(),
      ).toMap(),
    );
  }
}

final outbreakServiceProvider =
    Provider<OutbreakService>((ref) => OutbreakService());

final outbreaksProvider = StreamProvider<List<OutbreakReport>>(
  (ref) => ref.watch(outbreakServiceProvider).watchRecent(),
);
