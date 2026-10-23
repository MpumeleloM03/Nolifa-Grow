import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart';
import 'road_models.dart';
import 'road_repository.dart';

/// Each app overrides this with Firestore once Firebase is connected.
final roadRepositoryProvider = Provider<RoadRepository>((ref) => LocalRoadRepository());

final roadClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Only a verified driver may add, confirm or reject a warning, so one person
/// cannot fill the map with fake hazards.
final roadCanReportProvider = Provider<bool>((ref) => ref.watch(marketProvider.select((s) => s.driverVerified)));

enum ReportOutcome { created, merged, notAllowed }

/// A new report of the same kind within this distance of a live one is counted
/// as another driver seeing it, not as a second hazard.
const mergeRadiusM = 150.0;

class RoadState {
  final List<RoadHazard> hazards; // every warning received, newest first
  final bool shared;
  const RoadState({this.hazards = const [], this.shared = false});

  /// The ones still valid at [now].
  List<RoadHazard> live(DateTime now) => [for (final h in hazards) if (h.activeAt(now)) h];

  List<RoadHazard> near(double lat, double lng, double withinM, DateTime now) =>
      [for (final h in live(now)) if (metresBetween(lat, lng, h.lat, h.lng) <= withinM) h];
}

class RoadStore extends Notifier<RoadState> {
  StreamSubscription<List<RoadHazard>>? _sub;
  List<RoadHazard> _raw = const [];
  int _seq = 0;

  RoadRepository get _repo => ref.read(roadRepositoryProvider);
  DateTime get _now => ref.read(roadClockProvider)();

  @override
  RoadState build() {
    final repo = ref.watch(roadRepositoryProvider);
    _sub = repo.watch().listen((all) {
      _raw = all;
      _publish();
    });
    ref.onDispose(() => _sub?.cancel());
    return RoadState(shared: repo.shared);
  }

  void _publish() => state = RoadState(
        hazards: [..._raw]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen)),
        shared: _repo.shared,
      );

  /// Adds a warning where the driver is now, or counts as a sighting of one
  /// already there.
  Future<ReportOutcome> report(HazardKind kind, double lat, double lng, {String note = ''}) async {
    if (!ref.read(roadCanReportProvider)) return ReportOutcome.notAllowed;
    final uid = ref.read(marketUidProvider);
    final now = _now;
    for (final h in state.live(now)) {
      if (h.kind == kind && metresBetween(lat, lng, h.lat, h.lng) <= mergeRadiusM) {
        await _repo.save(h.seenBy(uid, now));
        return ReportOutcome.merged;
      }
    }
    await _repo.save(RoadHazard(
      id: 'h-${now.microsecondsSinceEpoch}-${_seq++}-$uid',
      kind: kind,
      lat: lat,
      lng: lng,
      reportedAt: now,
      lastSeen: now,
      reporter: uid,
      reporterName: ref.read(marketNameProvider),
      confirms: [uid],
      note: note.trim(),
    ));
    return ReportOutcome.created;
  }

  /// "Still there": keeps it alive for another full lifetime.
  Future<bool> confirm(String id) async {
    if (!ref.read(roadCanReportProvider)) return false;
    final h = _find(id);
    if (h == null) return false;
    await _repo.save(h.seenBy(ref.read(marketUidProvider), _now));
    return true;
  }

  /// "Not there": enough of these take it down.
  Future<bool> deny(String id) async {
    if (!ref.read(roadCanReportProvider)) return false;
    final h = _find(id);
    if (h == null) return false;
    await _repo.save(h.notThere(ref.read(marketUidProvider)));
    return true;
  }

  RoadHazard? _find(String id) {
    for (final h in _raw) {
      if (h.id == id) return h;
    }
    return null;
  }
}

final roadProvider = NotifierProvider<RoadStore, RoadState>(RoadStore.new);
