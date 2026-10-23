import 'package:cloud_firestore/cloud_firestore.dart';
import 'water_models.dart';
import 'water_repository.dart';

/// Shared, real-time water data in Firestore:
///
///  - waterZones/{zoneId}              reservoir readings, written only by the provider
///  - waterIncidents/{zoneId}-{epoch}  a community's request for help
///  - waterIncidents/{id}/votes/{uid}  one document per person who voted
///  - waterPrefs/{uid}                 a person's own household and tank details
class FirestoreWaterRepository implements WaterRepository {
  FirestoreWaterRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _zones => _db.collection('waterZones');
  CollectionReference<Map<String, dynamic>> get _incidents => _db.collection('waterIncidents');

  @override
  bool get shared => true;

  @override
  Stream<List<WaterZone>> watchZones() => _zones
      .snapshots()
      .map((q) => [for (final d in q.docs) waterZoneFromJson(d.data())]);

  @override
  Stream<List<WaterIncident>> watchIncidents() => _incidents
      .snapshots()
      .map((q) => [for (final d in q.docs) waterIncidentFromJson(d.data())]);

  @override
  Future<bool> hasVoted(String incidentId, String uid) async =>
      (await _incidents.doc(incidentId).collection('votes').doc(uid).get()).exists;

  @override
  Future<VoteResult> vote(WaterZone zone, String uid) async {
    final existing = await _incidents.where('zoneId', isEqualTo: zone.id).get();
    final all = [for (final d in existing.docs) waterIncidentFromJson(d.data())];
    final active = activeIncidentFor(all, zone.id);
    final nextEpoch = all.fold<int>(0, (a, i) => i.epoch > a ? i.epoch : a) + 1;

    return _db.runTransaction<VoteResult>((tx) async {
      DocumentReference<Map<String, dynamic>> incRef;
      Map<String, dynamic>? cur;
      if (active != null) {
        incRef = _incidents.doc(active.id);
        cur = (await tx.get(incRef)).data();
      } else {
        if (!zone.status.canRequestHelp) return VoteResult.notEligible;
        incRef = _incidents.doc('${zone.id}-$nextEpoch');
        cur = (await tx.get(incRef)).data(); // someone may have just opened it
      }
      final voteRef = incRef.collection('votes').doc(uid);
      if ((await tx.get(voteRef)).exists) return VoteResult.alreadyVoted;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (cur == null) {
        final enough = 1 >= zone.voteThreshold;
        tx.set(voteRef, {'uid': uid, 'at': now});
        tx.set(incRef, {
          'id': incRef.id,
          'zoneId': zone.id,
          'epoch': nextEpoch,
          'stage': enough ? 'requested' : 'open',
          'votes': 1,
          'threshold': zone.voteThreshold,
          'openedAt': now,
          'requestedAt': enough ? now : null,
          'acknowledgedAt': null,
          'dispatchedAt': null,
          'resolvedAt': null,
          'trucks': 0,
          'etaMinutes': 0,
          'note': '',
        });
      } else {
        final stage = cur['stage'] as String;
        if (stage != 'open' && stage != 'requested') return VoteResult.notEligible;
        final votes = ((cur['votes'] as num?) ?? 0).toInt() + 1;
        final crosses = stage == 'open' && votes >= ((cur['threshold'] as num?) ?? 100).toInt();
        tx.set(voteRef, {'uid': uid, 'at': now});
        tx.update(incRef, {
          'votes': votes,
          'stage': crosses ? 'requested' : stage,
          if (crosses) 'requestedAt': now,
        });
      }
      return VoteResult.counted;
    });
  }

  @override
  Future<void> upsertZone(WaterZone zone) => _zones.doc(zone.id).set(waterZoneToJson(zone));

  @override
  Future<void> publishReading(String zoneId, double level, {DateTime? at}) {
    final ref = _zones.doc(zoneId);
    return _db.runTransaction((tx) async {
      final d = (await tx.get(ref)).data();
      if (d == null) return;
      final z = waterZoneFromJson(d);
      final r = [...z.readings, WaterReading(at ?? DateTime.now(), level.clamp(0, 100).toDouble())];
      tx.set(ref, waterZoneToJson(z.withReadings(r)));
    });
  }

  /// Moves an incident to the next stage only if it is in an allowed one, so a
  /// late or repeated click can never skip a step.
  Future<void> _advance(String id, Set<String> from, Map<String, Object?> changes) {
    final ref = _incidents.doc(id);
    return _db.runTransaction((tx) async {
      final d = (await tx.get(ref)).data();
      if (d == null || !from.contains(d['stage'])) return;
      tx.update(ref, changes);
    });
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<void> acknowledge(String incidentId) => _advance(
      incidentId, {'requested'}, {'stage': 'acknowledged', 'acknowledgedAt': _now});

  @override
  Future<void> dispatch(String incidentId,
          {required int trucks, required int etaMinutes, String note = ''}) =>
      _advance(incidentId, {'requested', 'acknowledged'}, {
        'stage': 'dispatched',
        'dispatchedAt': _now,
        'trucks': trucks,
        'etaMinutes': etaMinutes,
        'note': note,
      });

  @override
  Future<void> resolve(String incidentId) =>
      _advance(incidentId, {'dispatched'}, {'stage': 'resolved', 'resolvedAt': _now});

  @override
  Future<WaterPrefs?> loadPrefs(String uid) async {
    final d = (await _db.collection('waterPrefs').doc(uid).get()).data();
    return d == null ? null : waterPrefsFromJson(d);
  }

  @override
  Future<void> savePrefs(String uid, WaterPrefs prefs) =>
      _db.collection('waterPrefs').doc(uid).set(waterPrefsToJson(prefs));
}
