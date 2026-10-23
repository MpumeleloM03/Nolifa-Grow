import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'market_codec.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// Shared, real-time storage in Firestore. Collections:
///
///  - marketProfiles/{uid}   private balances, plan, checks, ledger
///  - marketProducts/{id}    produce listed by farmers, visible to everyone
///  - marketOrders/{id}      orders, visible only to their buyer, farmer and
///                           driver, plus open jobs for any signed-in driver
///  - marketCases/{id}       outbreak reports and their verification stage
class FirestoreMarketRepository implements MarketRepository {
  FirestoreMarketRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  bool get shared => true;

  @override
  Future<PrivateState?> loadPrivate(String uid) async {
    final snap = await _db.collection('marketProfiles').doc(uid).get();
    final data = snap.data();
    if (data == null || data['state'] == null) return null;
    return PrivateState.fromJson(Map<String, dynamic>.from(data['state'] as Map));
  }

  @override
  Future<void> savePrivate(String uid, PrivateState s) => _db
      .collection('marketProfiles')
      .doc(uid)
      .set({'state': s.toJson(), 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Stream<List<Product>> watchProducts(String uid) =>
      _db.collection('marketProducts').snapshots().map((q) => [
            for (final d in q.docs) productFromJson(d.data(), uid),
          ]);

  @override
  Future<void> putProduct(Product p, String uid) => _db
      .collection('marketProducts')
      .doc(p.id)
      .set({...productToJson(p), 'ownerId': p.ownerId ?? uid});

  /// Two live queries, merged: orders I am part of, and open jobs for drivers.
  @override
  Stream<List<Order>> watchOrders(String uid) {
    final out = StreamController<List<Order>>();
    var mine = <String, Order>{};
    var open = <String, Order>{};
    void emit() => out.add({...open, ...mine}.values.toList());

    final a = _db
        .collection('marketOrders')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((q) {
      mine = {for (final d in q.docs) d.id: orderFromJson(d.data(), uid)};
      emit();
    }, onError: out.addError);
    final b = _db
        .collection('marketOrders')
        .where('status', isEqualTo: 'findingDriver')
        // The rules only allow reading unassigned jobs, so the query must say so
        // too: Firestore rejects any query it cannot prove stays inside the rules.
        .where('driverId', isNull: true)
        .snapshots()
        .listen((q) {
      open = {
        for (final d in q.docs)
          if (d.data()['driverId'] == null) d.id: orderFromJson(d.data(), uid)
      };
      emit();
    }, onError: out.addError);
    out.onCancel = () async {
      await a.cancel();
      await b.cancel();
    };
    return out.stream;
  }

  @override
  Future<void> putOrder(Order o, String uid) async {
    final ref = _db.collection('marketOrders').doc(o.id);
    final json = orderToJson(o, uid);
    // Never let a stale or conflicting copy overwrite what is already there.
    await _db.runTransaction((tx) async {
      final cur = await tx.get(ref);
      final curRev = (cur.data()?['rev'] as num?)?.toInt() ?? -1;
      if (cur.exists && curRev >= o.rev) return;
      tx.set(ref, json);
    });
  }

  @override
  Future<bool> claimJob(String orderId, String uid, String name) {
    final ref = _db.collection('marketOrders').doc(orderId);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null || d['driverId'] != null || d['status'] != 'findingDriver') {
        return false;
      }
      tx.update(ref, {
        'driverId': uid,
        'driver': name,
        'status': 'assigned',
        'rev': ((d['rev'] as num?) ?? 0).toInt() + 1,
        'participants': FieldValue.arrayUnion([uid]),
      });
      return true;
    });
  }

  @override
  Stream<List<ReportCase>> watchCases(String uid) =>
      _db.collection('marketCases').snapshots().map((q) => [
            for (final d in q.docs) caseFromJson(d.data(), uid),
          ]);

  @override
  Future<void> putCase(ReportCase c, String uid) =>
      _db.collection('marketCases').doc(c.id).set(caseToJson(c, uid));

  @override
  Future<void> confirmCase(String caseId, String uid) {
    final ref = _db.collection('marketCases').doc(caseId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null) return;
      final by = [...(d['confirmedBy'] as List? ?? const [])];
      if (by.contains(uid)) return;
      by.add(uid);
      final stage = (by.length >= 2 && d['stage'] == 'aiChecked') ? 'corroborated' : d['stage'];
      tx.update(ref, {'confirmedBy': by, 'confirmations': by.length, 'stage': stage});
    });
  }
}
