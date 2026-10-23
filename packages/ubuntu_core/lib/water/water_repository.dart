import 'dart:async';
import 'dart:convert';
import '../market/market_repository.dart' show KeyValue, MemoryKv, PrefsKv;
import 'water_models.dart';

// ----------------------------------------------------------------- JSON

Map<String, dynamic> waterZoneToJson(WaterZone z) => {
      'id': z.id,
      'name': z.name,
      'provider': z.provider,
      'reservoir': z.reservoir,
      'population': z.population,
      'voteThreshold': z.voteThreshold,
      'readings': [
        for (final r in z.readings.length > 48 ? z.readings.sublist(z.readings.length - 48) : z.readings)
          {'t': r.at.millisecondsSinceEpoch, 'level': r.level}
      ],
      'latest': z.readings.isEmpty ? null : z.level,
    };

WaterZone waterZoneFromJson(Map<String, dynamic> m, {bool demo = false}) => WaterZone(
      id: m['id'] as String,
      name: m['name'] as String,
      provider: m['provider'] as String? ?? 'Water provider',
      reservoir: m['reservoir'] as String? ?? '',
      population: (m['population'] as num?)?.toInt() ?? 0,
      voteThreshold: (m['voteThreshold'] as num?)?.toInt() ?? 100,
      demo: demo,
      readings: [
        for (final r in (m['readings'] as List? ?? const []))
          WaterReading(
            DateTime.fromMillisecondsSinceEpoch(((r as Map)['t'] as num).toInt()),
            (r['level'] as num).toDouble(),
          )
      ],
    );

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

Map<String, dynamic> waterIncidentToJson(WaterIncident i) => {
      'id': i.id,
      'zoneId': i.zoneId,
      'epoch': i.epoch,
      'stage': i.stage.name,
      'votes': i.votes,
      'threshold': i.threshold,
      'openedAt': _ms(i.openedAt),
      'requestedAt': _ms(i.requestedAt),
      'acknowledgedAt': _ms(i.acknowledgedAt),
      'dispatchedAt': _ms(i.dispatchedAt),
      'resolvedAt': _ms(i.resolvedAt),
      'trucks': i.trucks,
      'etaMinutes': i.etaMinutes,
      'note': i.note,
    };

WaterIncident waterIncidentFromJson(Map<String, dynamic> m) => WaterIncident(
      id: m['id'] as String,
      zoneId: m['zoneId'] as String,
      epoch: (m['epoch'] as num).toInt(),
      stage: IncidentStage.values.firstWhere((s) => s.name == m['stage'],
          orElse: () => IncidentStage.open),
      votes: (m['votes'] as num?)?.toInt() ?? 0,
      threshold: (m['threshold'] as num?)?.toInt() ?? 100,
      openedAt: _dt(m['openedAt']) ?? DateTime.now(),
      requestedAt: _dt(m['requestedAt']),
      acknowledgedAt: _dt(m['acknowledgedAt']),
      dispatchedAt: _dt(m['dispatchedAt']),
      resolvedAt: _dt(m['resolvedAt']),
      trucks: (m['trucks'] as num?)?.toInt() ?? 0,
      etaMinutes: (m['etaMinutes'] as num?)?.toInt() ?? 0,
      note: m['note'] as String? ?? '',
    );

Map<String, dynamic> waterPrefsToJson(WaterPrefs p) =>
    {'zoneId': p.zoneId, 'household': p.household, 'tankLitres': p.tankLitres, 'herd': p.herd};

WaterPrefs waterPrefsFromJson(Map<String, dynamic> m) => WaterPrefs(
      zoneId: m['zoneId'] as String?,
      household: (m['household'] as num?)?.toInt() ?? 4,
      tankLitres: (m['tankLitres'] as num?)?.toInt() ?? 0,
      herd: (m['herd'] as num?)?.toInt() ?? 0,
    );

/// The incident a community is currently dealing with: its newest one, if it
/// is not resolved yet.
WaterIncident? activeIncidentFor(Iterable<WaterIncident> all, String zoneId) {
  WaterIncident? best;
  for (final i in all) {
    if (i.zoneId != zoneId) continue;
    if (best == null || i.epoch > best.epoch) best = i;
  }
  return (best != null && best.active) ? best : null;
}

// ------------------------------------------------------------ interface

/// Where water data lives. A community's reservoir readings come from the
/// water provider; incidents and votes come from the people it serves.
abstract class WaterRepository {
  /// True when data is shared between phones.
  bool get shared;

  Stream<List<WaterZone>> watchZones();
  Stream<List<WaterIncident>> watchIncidents();

  /// Has this person already voted in this incident?
  Future<bool> hasVoted(String incidentId, String uid);

  /// Adds one person's voice. Opens an incident if the supply is low and none
  /// is open. Sends the request on once enough different people have voted.
  Future<VoteResult> vote(WaterZone zone, String uid);

  // What the water provider does (needs the utility permission when shared).
  Future<void> upsertZone(WaterZone zone);
  Future<void> publishReading(String zoneId, double level, {DateTime? at});
  Future<void> acknowledge(String incidentId);
  Future<void> dispatch(String incidentId,
      {required int trucks, required int etaMinutes, String note = ''});
  Future<void> resolve(String incidentId);

  // Private to the person.
  Future<WaterPrefs?> loadPrefs(String uid);
  Future<void> savePrefs(String uid, WaterPrefs prefs);
}

// ---------------------------------------------------------------- local

/// Keeps everything on this device. Behaves like the shared backend for one
/// user, so the rest of the app does not care which one is live. The demo uses
/// its own in-memory copy.
class LocalWaterRepository implements WaterRepository {
  LocalWaterRepository([KeyValue? kv]) : _kv = kv ?? PrefsKv();
  LocalWaterRepository.memory() : _kv = MemoryKv();

  final KeyValue _kv;
  final _changed = StreamController<void>.broadcast();
  List<Map<String, dynamic>>? _zones;
  List<Map<String, dynamic>>? _incidents;
  Map<String, List<String>>? _votes;

  @override
  bool get shared => false;

  Future<void> _ensure() async {
    _zones ??= await _list('water_zones');
    _incidents ??= await _list('water_incidents');
    if (_votes == null) {
      final raw = await _kv.read('water_votes');
      _votes = raw == null
          ? {}
          : {
              for (final e in (jsonDecode(raw) as Map).entries)
                e.key as String: [for (final x in (e.value as List)) x as String]
            };
    }
  }

  Future<List<Map<String, dynamic>>> _list(String key) async {
    final raw = await _kv.read(key);
    if (raw == null) return [];
    return [for (final e in (jsonDecode(raw) as List)) Map<String, dynamic>.from(e as Map)];
  }

  Future<void> _flush() async {
    await _kv.write('water_zones', jsonEncode(_zones));
    await _kv.write('water_incidents', jsonEncode(_incidents));
    await _kv.write('water_votes', jsonEncode(_votes));
    _changed.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    await _ensure();
    yield read();
    yield* _changed.stream.map((_) => read());
  }

  bool demoZones = false; // marks zones as demo when decoding

  @override
  Stream<List<WaterZone>> watchZones() =>
      _watch(() => [for (final m in _zones!) waterZoneFromJson(m, demo: demoZones)]);

  @override
  Stream<List<WaterIncident>> watchIncidents() =>
      _watch(() => [for (final m in _incidents!) waterIncidentFromJson(m)]);

  @override
  Future<bool> hasVoted(String incidentId, String uid) async {
    await _ensure();
    return (_votes![incidentId] ?? const []).contains(uid);
  }

  @override
  Future<VoteResult> vote(WaterZone zone, String uid) async {
    await _ensure();
    var active = activeIncidentFor([for (final m in _incidents!) waterIncidentFromJson(m)], zone.id);
    if (active == null) {
      if (!zone.status.canRequestHelp) return VoteResult.notEligible;
      final epoch = _incidents!
              .where((m) => m['zoneId'] == zone.id)
              .fold<int>(0, (a, m) => (m['epoch'] as num).toInt() > a ? (m['epoch'] as num).toInt() : a) +
          1;
      active = WaterIncident(
        id: '${zone.id}-$epoch',
        zoneId: zone.id,
        epoch: epoch,
        stage: IncidentStage.open,
        votes: 0,
        threshold: zone.voteThreshold,
        openedAt: DateTime.now(),
      );
      _incidents!.add(waterIncidentToJson(active));
    }
    final voters = _votes!.putIfAbsent(active.id, () => []);
    if (voters.contains(uid)) return VoteResult.alreadyVoted;
    voters.add(uid);
    final votes = active.votes + 1;
    final next = active.copyWith(
      votes: votes,
      stage: (active.stage == IncidentStage.open && votes >= active.threshold)
          ? IncidentStage.requested
          : active.stage,
      requestedAt: (active.stage == IncidentStage.open && votes >= active.threshold)
          ? DateTime.now()
          : null,
    );
    _replaceIncident(next);
    await _flush();
    return VoteResult.counted;
  }

  void _replaceIncident(WaterIncident i) {
    final json = waterIncidentToJson(i);
    final idx = _incidents!.indexWhere((m) => m['id'] == i.id);
    idx >= 0 ? _incidents![idx] = json : _incidents!.add(json);
  }

  Future<void> _update(String id, WaterIncident Function(WaterIncident) f) async {
    await _ensure();
    final idx = _incidents!.indexWhere((m) => m['id'] == id);
    if (idx < 0) return;
    _incidents![idx] = waterIncidentToJson(f(waterIncidentFromJson(_incidents![idx])));
    await _flush();
  }

  @override
  Future<void> upsertZone(WaterZone zone) async {
    await _ensure();
    final json = waterZoneToJson(zone);
    final idx = _zones!.indexWhere((m) => m['id'] == zone.id);
    idx >= 0 ? _zones![idx] = json : _zones!.add(json);
    await _flush();
  }

  @override
  Future<void> publishReading(String zoneId, double level, {DateTime? at}) async {
    await _ensure();
    final idx = _zones!.indexWhere((m) => m['id'] == zoneId);
    if (idx < 0) return;
    final z = waterZoneFromJson(_zones![idx]);
    final r = [...z.readings, WaterReading(at ?? DateTime.now(), level.clamp(0, 100).toDouble())];
    _zones![idx] = waterZoneToJson(z.withReadings(r));
    await _flush();
  }

  @override
  Future<void> acknowledge(String incidentId) => _update(
      incidentId,
      (i) => i.stage == IncidentStage.requested
          ? i.copyWith(stage: IncidentStage.acknowledged, acknowledgedAt: DateTime.now())
          : i);

  @override
  Future<void> dispatch(String incidentId,
          {required int trucks, required int etaMinutes, String note = ''}) =>
      _update(
          incidentId,
          (i) => (i.stage == IncidentStage.requested || i.stage == IncidentStage.acknowledged)
              ? i.copyWith(
                  stage: IncidentStage.dispatched,
                  dispatchedAt: DateTime.now(),
                  trucks: trucks,
                  etaMinutes: etaMinutes,
                  note: note)
              : i);

  @override
  Future<void> resolve(String incidentId) => _update(
      incidentId,
      (i) => i.stage == IncidentStage.dispatched
          ? i.copyWith(stage: IncidentStage.resolved, resolvedAt: DateTime.now())
          : i);

  @override
  Future<WaterPrefs?> loadPrefs(String uid) async {
    final raw = await _kv.read('water_prefs_$uid');
    return raw == null ? null : waterPrefsFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> savePrefs(String uid, WaterPrefs prefs) =>
      _kv.write('water_prefs_$uid', jsonEncode(waterPrefsToJson(prefs)));
}
