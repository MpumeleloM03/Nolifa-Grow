import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../services/job_map.dart';

final _geoCache = <String, LatLng>{};

Future<LatLng> placeOf(String text) async => _geoCache[text] ??= await geocode(text);

/// Where the driver is now, or null when location is off.
final driverPositionProvider = FutureProvider<LatLng?>((ref) => driverLocation());

/// Every open job with both ends placed on the map. Addresses are looked up
/// once and remembered.
final jobPointsProvider = FutureProvider<List<JobPoint>>((ref) async {
  final jobs = ref.watch(marketProvider.select((s) => s.openJobs));
  final out = <JobPoint>[];
  for (final o in jobs.take(40)) {
    final p = await placeOf(o.driverPickup);
    final d = await placeOf(o.dropArea);
    out.add(JobPoint(o, p.latitude, p.longitude, d.latitude, d.longitude));
  }
  return out;
});

/// Open jobs grouped into batches, richest first.
final batchesProvider = Provider<List<Batch>>((ref) {
  final jobs = ref.watch(jobPointsProvider).valueOrNull ?? const [];
  final me = ref.watch(driverPositionProvider).valueOrNull;
  return buildBatches(jobs, startLat: me?.latitude, startLng: me?.longitude);
});
