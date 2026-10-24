import 'dart:async';
import 'package:ubuntu_core/market/market_codec.dart';
import 'package:ubuntu_core/market/market_models.dart';
import 'package:ubuntu_core/market/market_repository.dart';
import 'package:ubuntu_core/roads/road_models.dart';
import 'package:ubuntu_core/roads/road_repository.dart';

/// Emits the current value on listen, then again after every change. Subscribes
/// to changes straight away so none is missed between the first value and the next.
Stream<T> liveOf<T>(Stream<void> changes, T Function() read) {
  late final StreamController<T> out;
  StreamSubscription<void>? sub;
  out = StreamController<T>(
    onListen: () {
      out.add(read());
      sub = changes.listen((_) => out.add(read()));
    },
    onCancel: () => sub?.cancel(),
  );
  return out.stream;
}

/// One in-memory "server" that several phones talk to, so store logic can be
/// tested across a farmer, a buyer, a hub desk and drivers. It follows the same
/// rules as the Supabase functions (newest revision wins, one driver per job,
/// one confirmation per neighbour). The real database rules are tested in
/// supabase/tests against a local Postgres.
class SharedMarketDb {
  final profiles = <String, PrivateState>{};
  final products = <String, Map<String, dynamic>>{};
  final orders = <String, Map<String, dynamic>>{};
  final cases = <String, Map<String, dynamic>>{};
  /// People an admin added as warehouse staff. They also see hub orders.
  final staff = <String>{'hub'};
  final changes = StreamController<void>.broadcast();
  void touch() => changes.add(null);
}

class FakeSharedMarketRepository implements MarketRepository {
  FakeSharedMarketRepository(this.db);
  final SharedMarketDb db;

  @override
  bool get shared => true;

  Stream<T> _live<T>(T Function() read) => liveOf(db.changes.stream, read);

  @override
  Future<PrivateState?> loadPrivate(String uid) async => db.profiles[uid];

  @override
  Future<void> savePrivate(String uid, PrivateState s) async => db.profiles[uid] = s;

  @override
  Stream<List<Product>> watchProducts(String uid) =>
      _live(() => [for (final d in db.products.values) productFromJson(d, uid)]);

  @override
  Future<void> putProduct(Product p, String uid) async {
    db.products[p.id] = {...productToJson(p), 'ownerId': p.ownerId ?? uid};
    db.touch();
  }

  @override
  Stream<List<Order>> watchOrders(String uid) => _live(() {
        final out = <Order>[];
        for (final d in db.orders.values) {
          final parts = [for (final p in (d['participants'] as List? ?? const [])) '$p'];
          final open = d['status'] == 'findingDriver' &&
              d['driverId'] == null &&
              (d['hubStage'] == null || d['hubStage'] == 'released');
          final hubDesk = d['route'] == 'hub' && db.staff.contains(uid);
          if (parts.contains(uid) || open || hubDesk) out.add(orderFromJson(d, uid));
        }
        return out;
      });

  @override
  Future<void> putOrder(Order o, String uid) async {
    final cur = db.orders[o.id];
    final curRev = (cur?['rev'] as num?)?.toInt() ?? -1;
    if (cur != null && curRev >= o.rev) return;
    db.orders[o.id] = orderToJson(o, uid);
    db.touch();
  }

  @override
  Future<bool> claimJob(String orderId, String uid, String name) async {
    final d = db.orders[orderId];
    if (d == null || d['driverId'] != null || d['status'] != 'findingDriver') return false;
    d['driverId'] = uid;
    d['driver'] = name;
    d['status'] = 'assigned';
    d['rev'] = ((d['rev'] as num?) ?? 0).toInt() + 1;
    d['participants'] = {...(d['participants'] as List? ?? const []), uid}.toList();
    db.touch();
    return true;
  }

  @override
  Future<bool> claimBatch(List<String> orderIds, String uid, String name) async {
    bool open(String id) {
      final d = db.orders[id];
      return d != null && d['driverId'] == null && d['status'] == 'findingDriver';
    }

    if (!orderIds.every(open)) return false;
    for (final id in orderIds) {
      await claimJob(id, uid, name);
    }
    return true;
  }

  @override
  Stream<List<ReportCase>> watchCases(String uid) =>
      _live(() => [for (final d in db.cases.values) caseFromJson(d, uid)]);

  @override
  Future<void> putCase(ReportCase c, String uid) async {
    db.cases[c.id] = caseToJson(c, uid);
    db.touch();
  }

  @override
  Future<void> confirmCase(String caseId, String uid) async {
    final d = db.cases[caseId];
    if (d == null) return;
    final by = [...(d['confirmedBy'] as List? ?? const [])];
    if (by.contains(uid)) return;
    by.add(uid);
    d['confirmedBy'] = by;
    d['confirmations'] = by.length;
    if (by.length >= 2 && d['stage'] == 'aiChecked') d['stage'] = 'corroborated';
    db.touch();
  }
}

class SharedRoadDb {
  final hazards = <String, RoadHazard>{};
  final changes = StreamController<void>.broadcast();
}

class FakeSharedRoadRepository implements RoadRepository {
  FakeSharedRoadRepository(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final SharedRoadDb db;
  final DateTime Function() _clock;

  @override
  bool get shared => true;

  List<RoadHazard> _read() {
    final since = _clock().subtract(const Duration(hours: 72));
    return [for (final h in db.hazards.values) if (h.lastSeen.isAfter(since)) h];
  }

  @override
  Stream<List<RoadHazard>> watch() => liveOf(db.changes.stream, _read);

  @override
  Future<void> save(RoadHazard h) async {
    db.hazards[h.id] = h;
    db.changes.add(null);
  }
}
