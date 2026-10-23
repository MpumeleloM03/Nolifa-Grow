import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../models/health_event.dart';
import '../models/livestock_disease.dart' show Urgency;
import 'auth_service.dart';
import 'firebase_boot.dart';

/// Every animal's health record. Kept sealed on the phone, or in
/// users/{uid}/healthLog once Firebase is on. Health records of livestock are
/// the farmer's own and never shared.
class HealthLogService {
  static String _key(String uid) => 'herd_health_$uid';

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('healthLog');

  Future<List<HealthEvent>> load(String uid) async {
    if (FirebaseBoot.ready) {
      final q = await _col(uid).get();
      return [for (final d in q.docs) HealthEvent.fromJson({...d.data(), 'id': d.id})];
    }
    final raw = await SecurePrefs.getString(_key(uid));
    if (raw == null) return const [];
    try {
      return [for (final m in jsonDecode(raw) as List) HealthEvent.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(String uid, HealthEvent e, List<HealthEvent> all) async {
    if (FirebaseBoot.ready) {
      await _col(uid).doc(e.id).set(e.toJson());
      return;
    }
    await SecurePrefs.setString(_key(uid), jsonEncode([for (final x in all) x.toJson()]));
  }

  Future<void> removeForAnimal(String uid, String animalId, List<HealthEvent> remaining) async {
    if (FirebaseBoot.ready) {
      final q = await _col(uid).where('animalId', isEqualTo: animalId).get();
      for (final d in q.docs) {
        await d.reference.delete();
      }
      return;
    }
    await SecurePrefs.setString(_key(uid), jsonEncode([for (final x in remaining) x.toJson()]));
  }
}

final healthLogServiceProvider = Provider<HealthLogService>((ref) => HealthLogService());

class HealthLog extends Notifier<List<HealthEvent>> {
  Future<void> _ready = Future.value();
  int _seq = 0;

  String? get _uid => ref.read(currentUserProvider)?.uid;

  @override
  List<HealthEvent> build() {
    final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
    if (uid == null) return const [];
    _ready = _load(uid);
    return const [];
  }

  Future<void> _load(String uid) async {
    final saved = await ref.read(healthLogServiceProvider).load(uid);
    final ids = {for (final e in state) e.id};
    state = [...state, for (final e in saved) if (!ids.contains(e.id)) e];
  }

  List<HealthEvent> forAnimal(String animalId) =>
      [for (final e in state) if (e.animalId == animalId) e]..sort((a, b) => b.at.compareTo(a.at));

  Future<HealthEvent> record(
    String animalId,
    HealthKind kind, {
    List<String> symptomIds = const [],
    String? condition,
    Urgency? urgency,
    String note = '',
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final e = HealthEvent(
      id: 'he-${now.microsecondsSinceEpoch}-${_seq++}',
      animalId: animalId,
      at: now,
      kind: kind,
      symptomIds: symptomIds,
      condition: condition,
      urgency: urgency,
      note: note.trim(),
    );
    state = [e, ...state];
    final uid = _uid;
    final all = state;
    if (uid != null) {
      await _ready;
      await ref.read(healthLogServiceProvider).add(uid, e, all);
    }
    return e;
  }

  Future<void> forgetAnimal(String animalId) async {
    state = [for (final e in state) if (e.animalId != animalId) e];
    final uid = _uid;
    if (uid != null) await ref.read(healthLogServiceProvider).removeForAnimal(uid, animalId, state);
  }
}

final healthLogProvider = NotifierProvider<HealthLog, List<HealthEvent>>(HealthLog.new);
