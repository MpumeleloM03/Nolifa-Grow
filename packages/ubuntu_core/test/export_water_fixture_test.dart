import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/water/firestore_water_repository.dart';
import 'package:ubuntu_core/water/water_models.dart';

/// Everything the water module writes, in order. A vote is one transaction in
/// the app (the vote document and the incident counter), so entries that share
/// a `tx` number must be replayed as one atomic batch.
class WriteLog {
  final entries = <Map<String, dynamic>>[];
  final _last = <String, String>{};
  int _tx = 0;

  int begin() => ++_tx;

  /// Adds the document's current content, unless it is the same as last time.
  Future<void> record(FakeFirebaseFirestore db, int tx, String uid, String path,
      {bool utility = false}) async {
    final snap = await db.doc(path).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.data()!);
    final enc = jsonEncode(data);
    if (_last[path] == enc) return;
    _last[path] = enc;
    entries.add({
      'tx': tx,
      'uid': uid,
      if (utility) 'utility': true,
      'path': path,
      'data': data,
    });
  }
}

/// Wraps the real Firestore water repository and records the documents each
/// call leaves behind. The log is replayed against the security rules in
/// firebase/rules-tests, so the app and the rules can never drift apart.
class Recorder {
  Recorder(this.inner, this.db, this.log);
  final FirestoreWaterRepository inner;
  final FakeFirebaseFirestore db;
  final WriteLog log;

  static const provider = 'provider-1';

  /// The zone as the phone would see it right now.
  Future<WaterZone> zone(String id) async =>
      (await inner.watchZones().first).firstWhere((z) => z.id == id);

  Future<void> _asProvider(String path, Future<void> Function() act) async {
    final tx = log.begin();
    await act();
    await log.record(db, tx, provider, path, utility: true);
  }

  Future<void> upsertZone(WaterZone z) =>
      _asProvider('waterZones/${z.id}', () => inner.upsertZone(z));

  Future<void> publishReading(String zoneId, double level, {DateTime? at}) =>
      _asProvider('waterZones/$zoneId', () => inner.publishReading(zoneId, level, at: at));

  Future<void> acknowledge(String id) =>
      _asProvider('waterIncidents/$id', () => inner.acknowledge(id));

  Future<void> dispatch(String id, {required int trucks, required int etaMinutes, String note = ''}) =>
      _asProvider('waterIncidents/$id',
          () => inner.dispatch(id, trucks: trucks, etaMinutes: etaMinutes, note: note));

  Future<void> resolve(String id) =>
      _asProvider('waterIncidents/$id', () => inner.resolve(id));

  /// A person's vote: their vote document and the incident it counted in.
  Future<VoteResult> vote(WaterZone zone, String uid) async {
    final tx = log.begin();
    final result = await inner.vote(zone, uid);
    if (result == VoteResult.counted) {
      final all = await db.collection('waterIncidents').where('zoneId', isEqualTo: zone.id).get();
      for (final d in all.docs) {
        await log.record(db, tx, uid, '${d.reference.path}/votes/$uid');
        await log.record(db, tx, uid, d.reference.path);
      }
    }
    return result;
  }

  Future<void> savePrefs(String uid, WaterPrefs p) async {
    final tx = log.begin();
    await inner.savePrefs(uid, p);
    await log.record(db, tx, uid, 'waterPrefs/$uid');
  }
}

WaterZone zoneWith(String id, String name, int threshold, List<double> levels) {
  final t0 = DateTime(2026, 10, 21, 6);
  return WaterZone(
    id: id,
    name: name,
    provider: 'Test water provider',
    reservoir: 'Test dam',
    population: 25000,
    voteThreshold: threshold,
    readings: [
      for (var i = 0; i < levels.length; i++) WaterReading(t0.add(Duration(hours: 6 * i)), levels[i]),
    ],
  );
}

void main() {
  test('record every write the water module makes in a full lifecycle', () async {
    final db = FakeFirebaseFirestore();
    final log = WriteLog();
    final repo = Recorder(FirestoreWaterRepository(db: db), db, log);
    Future<Map<String, dynamic>> incident(String id) async =>
        (await db.doc('waterIncidents/$id').get()).data()!;

    // The provider sets up a community. It is still Watch, so nobody can ask yet.
    await repo.upsertZone(zoneWith('umlazi', 'Umlazi', 3, [72, 61, 52]));
    final before = log.entries.length;
    expect(await repo.vote(await repo.zone('umlazi'), 'n1'), VoteResult.notEligible);
    expect(log.entries.length, before, reason: 'a refused vote writes nothing');

    // The dam drops to Low. Three different people vote, a fourth is late.
    await repo.publishReading('umlazi', 35, at: DateTime(2026, 10, 21, 18));
    expect((await repo.zone('umlazi')).status, WaterStatus.low);
    expect(await repo.vote(await repo.zone('umlazi'), 'n1'), VoteResult.counted);
    expect((await incident('umlazi-1'))['stage'], 'open');
    expect(await repo.vote(await repo.zone('umlazi'), 'n1'), VoteResult.alreadyVoted);
    expect(await repo.vote(await repo.zone('umlazi'), 'n2'), VoteResult.counted);
    expect(await repo.vote(await repo.zone('umlazi'), 'n3'), VoteResult.counted);
    expect((await incident('umlazi-1'))['stage'], 'requested');
    expect(await repo.vote(await repo.zone('umlazi'), 'n4'), VoteResult.counted);
    expect((await incident('umlazi-1'))['votes'], 4);

    // The provider takes it on, sends trucks, and closes it.
    await repo.acknowledge('umlazi-1');
    await repo.dispatch('umlazi-1', trucks: 2, etaMinutes: 90, note: 'Two 10 kL tankers (test)');
    await repo.resolve('umlazi-1');
    expect((await incident('umlazi-1'))['stage'], 'resolved');

    // The supply is still Low, so the next voice opens a second incident.
    expect(await repo.vote(await repo.zone('umlazi'), 'n5'), VoteResult.counted);
    expect((await incident('umlazi-2'))['votes'], 1);

    // A community that needs one voice goes straight to the provider, who
    // dispatches without acknowledging first.
    await repo.upsertZone(zoneWith('ntuzuma', 'Ntuzuma', 1, [60, 45, 30]));
    expect(await repo.vote(await repo.zone('ntuzuma'), 'n1'), VoteResult.counted);
    expect((await incident('ntuzuma-1'))['stage'], 'requested');
    await repo.dispatch('ntuzuma-1', trucks: 1, etaMinutes: 45);
    await repo.resolve('ntuzuma-1');

    // The dam recovers while an incident is still open. The vote that reaches
    // the threshold after that is still counted, so the rules must accept it.
    await repo.upsertZone(zoneWith('pinetown', 'Pinetown', 3, [60, 45, 35]));
    expect(await repo.vote(await repo.zone('pinetown'), 'n1'), VoteResult.counted);
    expect(await repo.vote(await repo.zone('pinetown'), 'n2'), VoteResult.counted);
    await repo.publishReading('pinetown', 85, at: DateTime(2026, 10, 22, 6));
    expect(await repo.vote(await repo.zone('pinetown'), 'n3'), VoteResult.counted);
    expect((await incident('pinetown-1'))['stage'], 'requested');

    // A person saves their household, then updates their tank.
    await repo.savePrefs('n1',
        const WaterPrefs(zoneId: 'umlazi', household: 5, tankLitres: 2500, herd: 0));
    await repo.savePrefs('n1',
        const WaterPrefs(zoneId: 'umlazi', household: 5, tankLitres: 5000, herd: 0));

    final entries = log.entries;
    expect(entries.first['path'], 'waterZones/umlazi');
    expect(entries.first['utility'], isTrue);
    expect(entries.where((e) => (e['path'] as String).contains('/votes/')).length, 9,
        reason: 'n1..n4 in umlazi-1, n5 in umlazi-2, n1 in ntuzuma-1 and n1..n3 in pinetown-1');
    expect(
      entries.where((e) => (e['path'] as String).startsWith('waterIncidents/') && e['utility'] == true).length,
      5,
      reason: 'acknowledge, dispatch, resolve for umlazi-1, then dispatch and resolve for ntuzuma-1',
    );
    expect(entries.last['path'], 'waterPrefs/n1');

    final out = File('../../firebase/rules-tests/fixtures/water-writes.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  });
}
