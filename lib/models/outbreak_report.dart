import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

enum OutbreakKind { plant, livestock }

/// A single disease sighting contributing to the regional heat map.
///
/// Locations are snapped to a coarse grid before they ever leave the device.
/// A farmer reporting foot-and-mouth should not be publishing the coordinates
/// of their kraal to every other user.
class OutbreakReport {
  final String id;
  final String disease;
  final String severity; // 'green' | 'orange' | 'red'
  final OutbreakKind kind;
  final LatLng location;
  final String region;
  final DateTime reportedAt;

  const OutbreakReport({
    required this.id,
    required this.disease,
    required this.severity,
    required this.kind,
    required this.location,
    required this.region,
    required this.reportedAt,
  });

  /// Roughly 5 km of rounding at KwaZulu-Natal's latitude.
  static const double _gridDegrees = 0.05;

  static LatLng coarsen(LatLng exact) => LatLng(
        (exact.latitude / _gridDegrees).round() * _gridDegrees,
        (exact.longitude / _gridDegrees).round() * _gridDegrees,
      );

  /// How much this sighting contributes to the heat, decayed over six weeks.
  /// Old reports should fade rather than imply an outbreak is still running.
  double get weight {
    final base = switch (severity) {
      'red' => 1.0,
      'orange' => 0.6,
      _ => 0.22,
    };
    final ageDays = DateTime.now().difference(reportedAt).inDays;
    final decay = (1 - (ageDays / 42)).clamp(0.15, 1.0);
    return base * decay;
  }

  Map<String, dynamic> toMap() => {
        'disease': disease,
        'severity': severity,
        'kind': kind.name,
        'lat': location.latitude,
        'lng': location.longitude,
        'region': region,
        'reportedAt': FieldValue.serverTimestamp(),
      };

  factory OutbreakReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OutbreakReport(
      id: doc.id,
      disease: d['disease'] as String? ?? 'Unknown',
      severity: d['severity'] as String? ?? 'orange',
      kind: d['kind'] == 'livestock' ? OutbreakKind.livestock : OutbreakKind.plant,
      location: LatLng(
        (d['lat'] as num?)?.toDouble() ?? 0,
        (d['lng'] as num?)?.toDouble() ?? 0,
      ),
      region: d['region'] as String? ?? '',
      reportedAt: (d['reportedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
