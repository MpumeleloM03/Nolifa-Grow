import 'dart:async';
import 'dart:convert';
import '../market/market_repository.dart' show KeyValue, MemoryKv, PrefsKv;
import '../market/places.dart';
import 'road_models.dart';

/// Where road warnings live. Local keeps them on this phone with a few labelled
/// samples so the feature can be shown; Firestore shares them between drivers.
abstract class RoadRepository {
  bool get shared;
  Stream<List<RoadHazard>> watch();
  Future<void> save(RoadHazard h);
}

class LocalRoadRepository implements RoadRepository {
  LocalRoadRepository({KeyValue? kv, DateTime Function()? clock, this.seeds = true})
      : _kv = kv ?? PrefsKv(),
        _clock = clock ?? DateTime.now;

  LocalRoadRepository.memory({DateTime Function()? clock, bool seeds = true})
      : this(kv: MemoryKv(), clock: clock, seeds: seeds);

  static const _key = 'road_hazards_v1';
  final KeyValue _kv;
  final DateTime Function() _clock;
  final bool seeds;
  final _ctl = StreamController<List<RoadHazard>>.broadcast();
  List<RoadHazard>? _all;
  Future<List<RoadHazard>>? _loading;

  @override
  bool get shared => false;

  Future<List<RoadHazard>> _ensure() => _loading ??= _load();

  Future<List<RoadHazard>> _load() async {
    final now = _clock();
    final saved = <RoadHazard>[];
    try {
      final raw = await _kv.read(_key);
      if (raw != null) {
        for (final m in jsonDecode(raw) as List) {
          saved.add(RoadHazard.fromJson(Map<String, dynamic>.from(m as Map)));
        }
      }
    } catch (_) {
      // An unreadable list is treated as empty.
    }
    return _all ??= [...saved.where((h) => h.activeAt(now)), if (seeds) ...sampleHazards(now)];
  }

  @override
  Stream<List<RoadHazard>> watch() {
    late final StreamController<List<RoadHazard>> out;
    StreamSubscription<List<RoadHazard>>? sub;
    out = StreamController<List<RoadHazard>>(
      onListen: () async {
        // Listen first, then send what is current, so a save in between is not lost.
        sub = _ctl.stream.listen(out.add);
        await _ensure();
        if (!out.isClosed) out.add(List.of(_all!));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<void> save(RoadHazard h) async {
    await _ensure();
    final all = _all!;
    final next = [h, for (final x in all) if (x.id != h.id) x];
    _all = next;
    _ctl.add(List.of(next));
    final real = [for (final x in next) if (!x.demo) x.toJson()];
    await _kv.write(_key, jsonEncode(real));
  }
}

/// Warnings that ship with the demo, around Durban. They are marked as samples
/// on screen and are never written to disk or shared.
List<RoadHazard> sampleHazards(DateTime now) {
  RoadHazard h(String id, HazardKind k, String place, int minsAgo, {String note = '', List<String> yes = const []}) {
    final p = placeCoords[place]!;
    final t = now.subtract(Duration(minutes: minsAgo));
    return RoadHazard(
      id: 'sample-$id',
      kind: k,
      lat: p.$1,
      lng: p.$2,
      reportedAt: t,
      lastSeen: t,
      reporter: 'sample',
      reporterName: 'Sample driver',
      confirms: ['sample', ...yes],
      note: note,
      demo: true,
    );
  }

  return [
    h('1', HazardKind.pothole, 'umlazi d section', 40, note: 'Deep hole in the left lane', yes: ['a', 'b']),
    h('2', HazardKind.flooding, 'inanda', 25, note: 'Low bridge under water after rain'),
    h('3', HazardKind.outage, 'pinetown', 55, note: 'Lights out at the main crossing'),
    h('4', HazardKind.roadworks, 'chatsworth', 300, note: 'Stop and go, 10 minute wait', yes: ['a']),
    h('5', HazardKind.police, 'kwamashu', 20),
    h('6', HazardKind.accident, 'hillcrest', 35, yes: ['a', 'b', 'c']),
  ];
}
