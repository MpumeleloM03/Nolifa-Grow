import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, resilientRows;
import '../services/auth_service.dart';

/// The two paid memberships. Both run for at least 24 months.
enum Tier {
  member('Member', 3000, 4, false),
  max('Max', 7000, 15, true);

  final String label;
  final int monthly;
  final int videosPerMonth;
  final bool vetVisits;
  const Tier(this.label, this.monthly, this.videosPerMonth, this.vetVisits);

  int get commitment => monthly * 24;

  static Tier? parse(String? s) => Tier.values.where((t) => t.name == s).firstOrNull;
}

class Membership {
  final Tier tier;
  final String status; // awaiting_payment | active | ended
  final DateTime? startedAt;
  final DateTime? termEndsAt;
  const Membership(this.tier, this.status, this.startedAt, this.termEndsAt);

  bool get active => status == 'active';
  bool get awaitingPayment => status == 'awaiting_payment';

  factory Membership.fromRow(Map<String, dynamic> r) => Membership(
        Tier.parse(r['tier'] as String?) ?? Tier.member,
        r['status'] as String? ?? 'awaiting_payment',
        DateTime.tryParse(r['started_at'] as String? ?? ''),
        DateTime.tryParse(r['term_ends_at'] as String? ?? ''),
      );
}

String? get _uid => SupabaseBoot.ready ? SupabaseBoot.client.auth.currentUser?.id : null;

/// This farmer's membership, live. Null when there is none, or when the app is
/// running on the phone alone.
final membershipProvider = StreamProvider<Membership?>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(null);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('memberships').stream(primaryKey: ['uid']).eq('uid', uid),
    fetch: () async => [for (final r in await db.from('memberships').select().eq('uid', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isEmpty ? null : Membership.fromRow(rows.first));
});

Future<void> joinMembership(Tier t) =>
    SupabaseBoot.client.rpc('join_membership', params: {'p_tier': t.name});

/// Videos this farmer can still send this month.
final videosLeftProvider = FutureProvider<int>((ref) async {
  ref.watch(membershipProvider);
  ref.watch(consultsProvider);
  if (!SupabaseBoot.ready || _uid == null) return 0;
  final v = await SupabaseBoot.client.rpc('videos_left');
  return (v as num?)?.toInt() ?? 0;
});

/// The plan staff have set for this farm. Starter until Nolifa changes it.
final serverPlanProvider = StreamProvider<String>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value('starter');
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('seller_plans').stream(primaryKey: ['uid']).eq('uid', uid),
    fetch: () async => [for (final r in await db.from('seller_plans').select().eq('uid', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isEmpty ? 'starter' : rows.first['plan'] as String);
});

class Consult {
  final String id;
  final String title, description, animalLabel, species, status, kind, province;
  final DateTime createdAt;
  final Map<String, dynamic>? diagnosis;
  final Map<String, dynamic>? visit;

  const Consult({
    required this.id,
    required this.title,
    required this.description,
    required this.animalLabel,
    required this.species,
    required this.status,
    required this.kind,
    required this.province,
    required this.createdAt,
    this.diagnosis,
    this.visit,
  });

  factory Consult.fromRow(Map<String, dynamic> r) => Consult(
        id: r['id'] as String,
        title: r['title'] as String? ?? '',
        description: r['description'] as String? ?? '',
        animalLabel: r['animal_label'] as String? ?? '',
        species: r['species'] as String? ?? '',
        status: r['status'] as String? ?? 'open',
        kind: r['kind'] as String? ?? 'video',
        province: r['province'] as String? ?? 'Unknown',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        diagnosis: r['diagnosis'] == null ? null : Map<String, dynamic>.from(r['diagnosis'] as Map),
        visit: r['visit'] == null ? null : Map<String, dynamic>.from(r['visit'] as Map),
      );

  String get statusLabel => switch (status) {
        'open' => 'Waiting for a vet',
        'in_review' => 'A vet is looking',
        'answered' => 'Answered',
        'visit_requested' => 'Visit requested',
        'visit_booked' => 'Visit booked',
        _ => 'Closed',
      };
}

final consultsProvider = StreamProvider<List<Consult>>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('consults').stream(primaryKey: ['id']).eq('farmer_id', uid),
    fetch: () async => [for (final r in await db.from('consults').select().eq('farmer_id', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => [for (final r in rows) Consult.fromRow(r)]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

class ChatLine {
  final String id, role, body;
  final DateTime at;
  const ChatLine(this.id, this.role, this.body, this.at);
}

final consultChatProvider = StreamProvider.family<List<ChatLine>, String>((ref, consultId) {
  if (!SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('consult_messages').stream(primaryKey: ['id']).eq('consult_id', consultId),
    fetch: () async => [for (final r in await db.from('consult_messages').select().eq('consult_id', consultId)) Map<String, dynamic>.from(r)],
  ).map((rows) => [
        for (final r in rows)
          ChatLine(r['id'] as String, r['role'] as String, r['body'] as String, DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now())
      ]..sort((a, b) => a.at.compareTo(b.at)));
});

final consultVideosProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, consultId) async {
  if (!SupabaseBoot.ready) return const [];
  final rows = await SupabaseBoot.client.from('consult_videos').select().eq('consult_id', consultId).order('created_at');
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});

/// The farm application, live.
final applicationProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(null);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('farm_applications').stream(primaryKey: ['uid']).eq('uid', uid),
    fetch: () async => [for (final r in await db.from('farm_applications').select().eq('uid', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isEmpty ? null : rows.first);
});

final boreholeRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (!SupabaseBoot.ready || _uid == null) return const [];
  final rows = await SupabaseBoot.client.from('borehole_requests').select().eq('uid', _uid!).order('created_at', ascending: false);
  return [for (final r in rows) Map<String, dynamic>.from(r)];
});
