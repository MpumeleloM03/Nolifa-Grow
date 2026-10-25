import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/outbox.dart';
import '../supabase/supabase_boot.dart';
import 'water_models.dart';
import 'water_repository.dart';

/// Shared, real-time water data in Supabase:
///
///  - water_zones       reservoir readings, written only by the provider
///  - water_incidents   a community's request for help ("<zone>-<epoch>")
///  - water_votes       one row per person who voted (private to them)
///  - water_prefs       a person's own household and tank details
class SupabaseWaterRepository implements WaterRepository {
  SupabaseWaterRepository({SupabaseClient? db}) : _db = db ?? SupabaseBoot.client;

  final SupabaseClient _db;

  @override
  bool get shared => true;

  Map<String, dynamic> _data(Map<String, dynamic> r) => Map<String, dynamic>.from(r['data'] as Map);

  @override
  Stream<List<WaterZone>> watchZones() =>
      liveTable(_db, 'water_zones').map((rows) => [for (final r in rows) waterZoneFromJson(_data(r))]);

  @override
  Stream<List<WaterIncident>> watchIncidents() =>
      liveTable(_db, 'water_incidents').map((rows) => [for (final r in rows) waterIncidentFromJson(_data(r))]);

  @override
  Future<bool> hasVoted(String incidentId, String uid) async =>
      await _db.rpc('water_has_voted', params: {'p_incident': incidentId}) == true;

  /// One database function opens or joins the incident and counts the vote in
  /// a single step, so a person cannot vote twice and the count cannot drift.
  @override
  Future<VoteResult> vote(WaterZone zone, String uid, {bool dryTaps = false}) async {
    try {
      final res = await _db.rpc('water_vote', params: {'p_zone': zone.id, 'p_reason': dryTaps ? 'dry_taps' : 'low_supply'});
      return switch (res) {
        'counted' => VoteResult.counted,
        'alreadyVoted' => VoteResult.alreadyVoted,
        _ => VoteResult.notEligible,
      };
    } on PostgrestException catch (e) {
      if (e.code == '42501') return VoteResult.notVerified;
      rethrow;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      // No signal: keep the request on the phone and send it when it is back.
      final sent = await OfflineOutbox.instance.rpc(
          'Water help request', 'water_vote', {'p_zone': zone.id, 'p_reason': dryTaps ? 'dry_taps' : 'low_supply'});
      return sent ? VoteResult.counted : VoteResult.queued;
    }
  }

  @override
  Future<void> upsertZone(WaterZone zone) =>
      _db.from('water_zones').upsert({'id': zone.id, 'data': waterZoneToJson(zone)});

  @override
  Future<void> publishReading(String zoneId, double level, {DateTime? at}) async {
    final row = await _db.from('water_zones').select('data').eq('id', zoneId).maybeSingle();
    if (row == null) return;
    final z = waterZoneFromJson(_data(row));
    final r = [...z.readings, WaterReading(at ?? DateTime.now(), level.clamp(0, 100).toDouble())];
    await _db.from('water_zones').update({'data': waterZoneToJson(z.withReadings(r))}).eq('id', zoneId);
  }

  /// Moves an incident to the next stage only if it is in an allowed one, so a
  /// late or repeated click can never skip a step.
  Future<void> _advance(String id, Set<String> from, Map<String, Object?> changes) async {
    final row = await _db.from('water_incidents').select('data, stage').eq('id', id).maybeSingle();
    if (row == null || !from.contains(row['stage'])) return;
    await _db
        .from('water_incidents')
        .update({'data': {..._data(row), ...changes}})
        .eq('id', id)
        .inFilter('stage', from.toList());
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<void> acknowledge(String incidentId) =>
      _advance(incidentId, {'requested'}, {'stage': 'acknowledged', 'acknowledgedAt': _now});

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
    final row = await _db.from('water_prefs').select('data').eq('uid', uid).maybeSingle();
    return row == null ? null : waterPrefsFromJson(_data(row));
  }

  @override
  Future<void> savePrefs(String uid, WaterPrefs prefs) async {
    await OfflineOutbox.instance.upsert('Water details', 'water_prefs', {'uid': uid, 'data': waterPrefsToJson(prefs)});
  }
}
