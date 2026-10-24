import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_boot.dart';
import 'market_codec.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// Shared, real-time storage in Supabase. Tables:
///
///  - market_profiles   private balances, plan, checks, ledger (owner only)
///  - market_products   produce listed by farmers, visible to everyone
///  - market_orders     visible to their buyer, farmer and driver, plus open jobs
///  - market_cases      outbreak reports and their verification stage
class SupabaseMarketRepository implements MarketRepository {
  SupabaseMarketRepository({SupabaseClient? db}) : _db = db ?? SupabaseBoot.client;

  final SupabaseClient _db;

  @override
  bool get shared => true;

  @override
  Future<PrivateState?> loadPrivate(String uid) async {
    final row = await _db.from('market_profiles').select('state').eq('uid', uid).maybeSingle();
    if (row == null || row['state'] == null) return null;
    return PrivateState.fromJson(Map<String, dynamic>.from(row['state'] as Map));
  }

  @override
  Future<void> savePrivate(String uid, PrivateState s) => _db
      .from('market_profiles')
      .upsert({'uid': uid, 'state': s.toJson(), 'updated_at': DateTime.now().toUtc().toIso8601String()});

  @override
  Stream<List<Product>> watchProducts(String uid) => liveTable(_db, 'market_products')
      .map((rows) => [for (final r in rows) productFromJson(Map<String, dynamic>.from(r['data'] as Map), uid)]);

  @override
  Future<void> putProduct(Product p, String uid) => _db.from('market_products').upsert({
        'id': p.id,
        'owner_id': p.ownerId ?? uid,
        'data': {...productToJson(p), 'ownerId': p.ownerId ?? uid},
      });

  /// Row level security already limits the table to what this person may see:
  /// orders they are part of, open jobs for drivers, and hub orders for staff.
  @override
  Stream<List<Order>> watchOrders(String uid) => liveTable(_db, 'market_orders').map((rows) => [
        for (final r in rows) orderFromJson(Map<String, dynamic>.from(r['data'] as Map), uid),
      ]);

  @override
  Future<void> putOrder(Order o, String uid) =>
      _db.rpc('put_order', params: {'p_data': {...orderToJson(o, uid), 'id': o.id}});

  @override
  Future<bool> claimJob(String orderId, String uid, String name) async =>
      (await _db.rpc('claim_job', params: {'p_id': orderId, 'p_name': name})) == true;

  @override
  Future<bool> claimBatch(List<String> orderIds, String uid, String name) async =>
      (await _db.rpc('claim_batch', params: {'p_ids': orderIds, 'p_name': name})) == true;

  @override
  Stream<List<ReportCase>> watchCases(String uid) => liveTable(_db, 'market_cases')
      .map((rows) => [for (final r in rows) caseFromJson(Map<String, dynamic>.from(r['data'] as Map), uid)]);

  @override
  Future<void> putCase(ReportCase c, String uid) =>
      _db.from('market_cases').upsert({'id': c.id, 'data': caseToJson(c, uid)});

  @override
  Future<void> confirmCase(String caseId, String uid) =>
      _db.rpc('confirm_case', params: {'p_id': caseId});
}
