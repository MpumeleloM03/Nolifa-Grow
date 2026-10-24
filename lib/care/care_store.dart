import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs, SupabaseBoot;
import '../models/cattle.dart';
import '../models/health_event.dart';
import '../services/auth_service.dart';
import '../services/cattle_service.dart';
import '../services/health_log_service.dart';
import '../services/phone_notifier.dart';
import 'care_models.dart';

const _waterBase = 7000; // notification ids 7000-7049
const _feedBase = 7050; // 7050-7099

/// The farm's water and feed schedule and today's ticks. Kept sealed on the
/// phone and copied to the farm's private care log in the database.
class CareState {
  final CareSettings settings;
  final List<CareTick> ticks;
  const CareState(this.settings, this.ticks);
}

class CareStore extends Notifier<CareState> {
  Future<void> _ready = Future.value();

  String? get _uid => ref.read(currentUserProvider)?.uid;
  String _k(String uid, String what) => 'care_${what}_$uid';

  @override
  CareState build() {
    final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
    if (uid == null) return const CareState(CareSettings(), []);
    _ready = _load(uid);
    return const CareState(CareSettings(), []);
  }

  Future<void> _load(String uid) async {
    try {
      final s = await SecurePrefs.getString(_k(uid, 'settings'));
      final t = await SecurePrefs.getString(_k(uid, 'ticks'));
      final settings = s == null ? const CareSettings() : CareSettings.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
      final ticks = t == null
          ? <CareTick>[]
          : [for (final m in jsonDecode(t) as List) CareTick.fromJson(Map<String, dynamic>.from(m as Map))];
      state = CareState(settings, ticks);
      await reschedule();
    } catch (e) {
      debugPrint('care: could not read saved schedule: $e');
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    await _ready;
    try {
      await SecurePrefs.setString(_k(uid, 'settings'), jsonEncode(state.settings.toJson()));
      // Keep two weeks of ticks on the phone.
      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      final kept = [for (final t in state.ticks) if (t.at.isAfter(cutoff)) t];
      await SecurePrefs.setString(_k(uid, 'ticks'), jsonEncode([for (final t in kept) t.toJson()]));
    } catch (e) {
      debugPrint('care: could not save: $e');
    }
  }

  Future<void> update(CareSettings next) async {
    state = CareState(next, state.ticks);
    await _save();
    await reschedule();
    final uid = _uid;
    if (uid != null && SupabaseBoot.ready) {
      try {
        await SupabaseBoot.client.from('care_log').upsert({'uid': uid, 'id': 'settings', 'data': next.toJson()});
      } catch (e) {
        debugPrint('care: settings not shared yet: $e');
      }
    }
  }

  bool done(String kind, String time, [DateTime? on]) =>
      state.ticks.any((t) => t.key == '${dayKey(on ?? DateTime.now())}|$kind|$time');

  Future<void> tick(String kind, String time) async {
    if (done(kind, time)) return;
    final now = DateTime.now();
    final t = CareTick(dayKey(now), kind, time, now);
    state = CareState(state.settings, [...state.ticks, t]);
    await _save();
    final uid = _uid;
    if (uid != null && SupabaseBoot.ready) {
      try {
        await SupabaseBoot.client.from('care_log').upsert({'uid': uid, 'id': t.key, 'data': t.toJson()});
      } catch (e) {
        debugPrint('care: tick not shared yet: $e');
      }
    }
  }

  /// Sets the daily phone reminders from the current times.
  Future<void> reschedule() async {
    final n = PhoneNotifier.instance;
    await n.cancelRange(_waterBase, _feedBase + 50);
    final s = state.settings;
    if (!s.remindersOn) return;
    for (var i = 0; i < s.waterTimes.length && i < 40; i++) {
      final hm = _hm(s.waterTimes[i]);
      if (hm == null) continue;
      await n.scheduleDaily(
          id: _waterBase + i, hour: hm.$1, minute: hm.$2, title: 'Water the herd', body: 'Check the troughs are full and clean, then tick it off in Nolifa Grow.');
    }
    for (var i = 0; i < s.feedTimes.length && i < 40; i++) {
      final hm = _hm(s.feedTimes[i]);
      if (hm == null) continue;
      await n.scheduleDaily(
          id: _feedBase + i, hour: hm.$1, minute: hm.$2, title: 'Feed time', body: 'Time to feed your animals. Tick it off in Nolifa Grow when it is done.');
    }
  }

  static (int, int)? _hm(String t) {
    final p = t.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return (h, m);
  }
}

final careProvider = NotifierProvider<CareStore, CareState>(CareStore.new);

/// Where one animal stands on vaccination.
enum VaccineStanding { current, due, declined, unknown }

class VaccineStatus {
  final VaccineStanding standing;
  final HealthEvent? last;
  const VaccineStatus(this.standing, this.last);
}

VaccineStatus vaccineStatusOf(List<HealthEvent> events, DateTime now) {
  final mine = [for (final e in events) if (e.kind == HealthKind.vaccination || e.kind == HealthKind.notVaccinated) e]
    ..sort((a, b) => b.at.compareTo(a.at));
  if (mine.isEmpty) return const VaccineStatus(VaccineStanding.unknown, null);
  final last = mine.first;
  if (last.kind == HealthKind.notVaccinated) return VaccineStatus(VaccineStanding.declined, last);
  final age = now.difference(last.at).inDays;
  return VaccineStatus(age <= vaccineValidDays ? VaccineStanding.current : VaccineStanding.due, last);
}

/// The herd's vaccination picture for the home card.
class VaccineSummary {
  final int total, current, due, declined, unknown;
  const VaccineSummary(this.total, this.current, this.due, this.declined, this.unknown);
  int get needAttention => due + declined + unknown;
}

final vaccineSummaryProvider = Provider<VaccineSummary?>((ref) {
  final herd = ref.watch(herdProvider).valueOrNull;
  if (herd == null) return null;
  final events = ref.watch(healthLogProvider);
  final active = [for (final c in herd) if (c.status == CattleStatus.active) c];
  var cur = 0, due = 0, dec = 0, unk = 0;
  final now = DateTime.now();
  for (final c in active) {
    switch (vaccineStatusOf([for (final e in events) if (e.animalId == c.id) e], now).standing) {
      case VaccineStanding.current:
        cur++;
      case VaccineStanding.due:
        due++;
      case VaccineStanding.declined:
        dec++;
      case VaccineStanding.unknown:
        unk++;
    }
  }
  return VaccineSummary(active.length, cur, due, dec, unk);
});
