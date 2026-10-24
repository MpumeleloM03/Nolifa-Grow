import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, resilientRows;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/outbreak_report.dart';
import 'local_backend.dart';

/// Community disease sightings, stored flat in the `outbreaks` table.
///
/// Readable by every signed-in farmer — the whole point is that your
/// neighbour's report warns you before the disease reaches your fence.
class OutbreakService {
  SupabaseClient get _db => SupabaseBoot.client;

  Stream<List<OutbreakReport>> watchRecent({int days = 60}) {
    if (!SupabaseBoot.ready) return LocalBackend.instance.watchOutbreaks();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return resilientRows(
      open: () => _db.from('outbreaks').stream(primaryKey: ['id']),
      fetch: () async => [for (final r in await _db.from('outbreaks').select()) Map<String, dynamic>.from(r)],
    ).map((rows) => [
          for (final r in rows)
            OutbreakReport.fromMap(r['id'] as String, Map<String, dynamic>.from(r['data'] as Map)),
        ].where((o) => o.reportedAt.isAfter(cutoff)).toList());
  }

  Future<void> report({
    required String disease,
    required String severity,
    required OutbreakKind kind,
    required LatLng exactLocation,
    required String region,
  }) {
    if (!SupabaseBoot.ready) {
      return LocalBackend.instance.addOutbreak(
        disease: disease,
        severity: severity,
        kind: kind,
        location: OutbreakReport.coarsen(exactLocation),
        region: region,
      );
    }
    return _db.from('outbreaks').insert({
      'data': OutbreakReport(
        id: '',
        disease: disease,
        severity: severity,
        kind: kind,
        location: OutbreakReport.coarsen(exactLocation),
        region: region,
        reportedAt: DateTime.now(),
      ).toMap(),
    });
  }
}

final outbreakServiceProvider =
    Provider<OutbreakService>((ref) => OutbreakService());

final outbreaksProvider = StreamProvider<List<OutbreakReport>>(
  (ref) => ref.watch(outbreakServiceProvider).watchRecent(),
);
