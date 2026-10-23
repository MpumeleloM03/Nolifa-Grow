import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'open_store.dart';
import 'package:ubuntu_core/market/firestore_market_repository.dart';
import 'package:ubuntu_core/market/market_codec.dart';
import 'package:ubuntu_core/market/market_models.dart';
import 'package:ubuntu_core/market/market_repository.dart';
import 'package:ubuntu_core/market/market_store.dart';

/// Wraps the real Firestore repository and records the document that each
/// write leaves behind. The log is replayed against the security rules in
/// firebase/rules-tests, so the app and the rules can never drift apart.
class Recorder implements MarketRepository {
  Recorder(this.inner, this.db, this.log);
  final FirestoreMarketRepository inner;
  final FakeFirebaseFirestore db;
  final List<Map<String, dynamic>> log;
  final _last = <String, String>{};

  @override
  bool get shared => true;

  Future<void> _record(String uid, String path) async {
    final snap = await db.doc(path).get();
    final data = Map<String, dynamic>.from(snap.data() ?? {})..remove('updatedAt');
    final enc = jsonEncode(data);
    if (_last[path] == enc) return;
    _last[path] = enc;
    log.add({'uid': uid, 'path': path, 'data': data});
  }

  @override
  Future<PrivateState?> loadPrivate(String uid) => inner.loadPrivate(uid);
  @override
  Future<void> savePrivate(String uid, PrivateState s) async {
    await inner.savePrivate(uid, s);
    await _record(uid, 'marketProfiles/$uid');
  }

  @override
  Stream<List<Product>> watchProducts(String uid) => inner.watchProducts(uid);
  @override
  Future<void> putProduct(Product p, String uid) async {
    await inner.putProduct(p, uid);
    await _record(uid, 'marketProducts/${p.id}');
  }

  @override
  Stream<List<Order>> watchOrders(String uid) => inner.watchOrders(uid);
  @override
  Future<void> putOrder(Order o, String uid) async {
    await inner.putOrder(o, uid);
    await _record(uid, 'marketOrders/${o.id}');
  }

  @override
  Future<bool> claimJob(String orderId, String uid, String name) async {
    final ok = await inner.claimJob(orderId, uid, name);
    if (ok) await _record(uid, 'marketOrders/$orderId');
    return ok;
  }

  @override
  Stream<List<ReportCase>> watchCases(String uid) => inner.watchCases(uid);
  @override
  Future<void> putCase(ReportCase c, String uid) async {
    await inner.putCase(c, uid);
    await _record(uid, 'marketCases/${c.id}');
  }

  @override
  Future<void> confirmCase(String caseId, String uid) async {
    await inner.confirmCase(caseId, uid);
    await _record(uid, 'marketCases/$caseId');
  }
}

Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

ProviderContainer phone(String uid, MarketRepository repo) {
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue(uid),
    marketNameProvider.overrideWithValue(uid),
    marketRepositoryProvider.overrideWithValue(repo),
  ]);
  c.listen(marketProvider, (_, __) {});
  c.read(marketProvider.notifier).setDemoMode(false);
  return c;
}

void main() {
  test('record every write the app makes in a full lifecycle', () async {
    final db = FakeFirebaseFirestore();
    final log = <Map<String, dynamic>>[];
    MarketRepository repo() =>
        Recorder(FirestoreMarketRepository(db: db), db, log);

    final farmer = phone('farmer', repo());
    final buyer = phone('buyer', repo());
    final driver = phone('driver', repo());
    final neighbour1 = phone('n1', repo());
    final neighbour2 = phone('n2', repo());
    await settle();
    MarketStore st(ProviderContainer c) => c.read(marketProvider.notifier);
    MarketState s(ProviderContainer c) => c.read(marketProvider);

    // Listing, ordering, packing, claiming, pickup, PIN delivery, confirmation.
    st(farmer).openAndList(const Product(
        id: 'carrots',
        name: 'Carrots 5kg',
        emoji: '🥕',
        category: Category.veg,
        farm: 'Real Farm',
        km: 1,
        price: 60,
        unit: 'pack'));
    await settle();
    st(buyer).add('carrots', 2);
    final id = st(buyer).place(PayMethod.fnbPay);
    await settle();
    st(farmer).packOrder(id);
    await settle();
    st(driver).accept(id);
    await settle();
    st(driver).pickedUp(id);
    await settle();
    expect(st(driver).deliverWithPin(id, s(buyer).pins[id]!), isTrue);
    await settle();
    st(buyer).confirmReceived(id, 5);
    await settle();
    expect(s(farmer).orderById(id)!.released, isTrue);

    // A second order that the buyer disputes mid-delivery.
    st(buyer).add('carrots');
    final id2 = st(buyer).place(PayMethod.instantMoney);
    await settle();
    st(farmer).packOrder(id2);
    await settle();
    st(driver).accept(id2);
    await settle();
    st(driver).pickedUp(id2);
    await settle();
    st(buyer).openDispute(id2, DisputeReason.notDelivered, 'never came');
    await settle();
    expect(s(driver).orderById(id2)!.disputed, isTrue);

    // An outbreak case, confirmed by two neighbours.
    final caseId = st(farmer).submitReport('Leaf rust', '🍂', 'Hillcrest');
    await settle();
    st(neighbour1).confirmCase(caseId);
    await settle();
    st(neighbour2).confirmCase(caseId);
    await settle();

    expect(log.length, greaterThan(15));
    final out = File('../../firebase/rules-tests/fixtures/dart-writes.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(log));

    for (final c in [farmer, buyer, driver, neighbour1, neighbour2]) {
      c.dispose();
    }
  });
}
