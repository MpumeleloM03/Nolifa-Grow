import 'shared_fakes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'open_store.dart';
import 'package:ubuntu_core/market/market_models.dart';
import 'package:ubuntu_core/market/market_repository.dart';
import 'package:ubuntu_core/market/market_store.dart';

/// One phone: its own user, its own container, a shared backend.
class Phone {
  final ProviderContainer c;
  final String uid;
  Phone(this.uid, MarketRepository repo, {bool demo = false})
      : c = ProviderContainer(overrides: [
          marketUidProvider.overrideWithValue(uid),
          marketNameProvider.overrideWithValue(uid),
          marketRepositoryProvider.overrideWithValue(repo),
        ]) {
    c.listen(marketProvider, (_, __) {});
    if (!demo) store.setDemoMode(false);
  }

  MarketStore get store => c.read(marketProvider.notifier);
  MarketState get s => c.read(marketProvider);
  void dispose() => c.dispose();
}

/// Lets queued streams and writes settle.
Future<void> settle([int ms = 60]) async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms));
  }
}

void main() {
  group('supply risk radar', () {
    test('only verified cases move a supplier rating', () async {
      final p = Phone('biz', LocalMarketRepository.memory(), demo: true);
      await settle();
      Risk risk(String id) => p.s.riskOf(suppliers.firstWhere((x) => x.id == id)).$1;

      expect(risk('s-1'), Risk.high); // Pinetown: vet verified foot-and-mouth
      expect(risk('s-2'), Risk.watch); // Verulam: confirmed by nearby farms
      expect(risk('s-4'), Risk.clear);
      expect(risk('s-6'), Risk.clear); // Hillcrest case is only AI checked

      // A fresh, unverified report in a clean district changes nothing.
      p.store.submitReport('Suspected anthrax', '🐄', 'Estcourt');
      expect(risk('s-5'), Risk.clear);
      p.dispose();
    });

    test('rerouting clears the action count without delisting anyone', () async {
      final p = Phone('biz', LocalMarketRepository.memory(), demo: true);
      await settle();
      expect(p.s.highRiskCount, 1);
      p.store.reroute('s-1', true);
      expect(p.s.highRiskCount, 0);
      expect(p.s.rerouted, {'s-1'});
      p.store.reroute('s-1', false);
      expect(p.s.highRiskCount, 1);
      p.store.requestQuote('a-2');
      expect(p.s.quotes, {'a-2'});
      p.dispose();
    });
  });

  group('persistence', () {
    test('plan, checks, consent, cart and orders survive a restart', () async {
      final kv = MemoryKv();
      final a = Phone('u1', LocalMarketRepository(kv), demo: true);
      await settle();
      a.store.setPlan(Plan.grow);
      a.store.setConsent(false);
      a.store.completeKyc(KycRole.driver, 'selfie');
      a.store.add('p-water');
      final id = a.store.place(PayMethod.fnbPay);
      a.store.add('p-candle');
      final pin = a.s.pins[id];
      expect(pin, isNotNull);
      await settle();
      a.dispose();

      final b = Phone('u1', LocalMarketRepository(kv), demo: true);
      await settle();
      expect(b.s.plan, Plan.grow);
      expect(b.s.creditConsent, isFalse);
      expect(b.s.driverKyc, containsAll(['id', 'selfie']));
      expect(b.s.cart, {'p-candle': 1});
      final o = b.s.orderById(id)!;
      expect(o.customerIsMe, isTrue);
      expect(o.pin, pin); // buyer still sees their own PIN
      b.dispose();
    });

    test('another user never sees my balances or PIN', () async {
      final kv = MemoryKv();
      final a = Phone('u1', LocalMarketRepository(kv), demo: true);
      await settle();
      a.store.setPlan(Plan.coop);
      await settle();
      a.dispose();
      final other = Phone('u2', LocalMarketRepository(kv), demo: true);
      await settle();
      expect(other.s.plan, Plan.starter);
      other.dispose();
    });
  });

  group('claiming a job', () {
    Future<void> claimsAreExclusive(MarketRepository repo, String name) async {
      final order = Order(
        id: 'UD-TEST',
        lines: const [OrderLine('Eggs', '🥚', 1, 80)],
        deliveryFee: 25,
        method: PayMethod.fnbPay,
        status: OrderStatus.findingDriver,
        customer: 'Buyer',
        pickup: 'Farm',
        dropArea: 'Street',
        placed: DateTime.now(),
        customerId: 'buyer',
        customerIsMe: true,
      );
      await repo.putOrder(order, 'buyer');
      expect(await repo.claimJob('UD-TEST', 'd1', 'One'), isTrue, reason: '$name first claim');
      expect(await repo.claimJob('UD-TEST', 'd2', 'Two'), isFalse, reason: '$name second claim');
      expect(await repo.claimJob('missing', 'd2', 'Two'), isFalse);
    }

    test('only the first driver gets a job (local)', () async {
      await claimsAreExclusive(LocalMarketRepository.memory(), 'local');
    });

    test('only the first driver gets a job (shared fake)', () async {
      await claimsAreExclusive(FakeSharedMarketRepository(SharedMarketDb()), 'shared');
    });

    test('a stale write cannot overwrite a newer order', () async {
      final repo = FakeSharedMarketRepository(SharedMarketDb());
      final base = Order(
        id: 'UD-REV',
        lines: const [OrderLine('Eggs', '🥚', 1, 80)],
        deliveryFee: 25,
        method: PayMethod.fnbPay,
        status: OrderStatus.findingDriver,
        customer: 'Buyer',
        pickup: 'Farm',
        dropArea: 'Street',
        placed: DateTime.now(),
        customerId: 'buyer',
        customerIsMe: true,
        rev: 3,
      );
      await repo.putOrder(base.copyWith(status: OrderStatus.delivered, rev: 5), 'buyer');
      await repo.putOrder(base.copyWith(status: OrderStatus.assigned, rev: 4), 'buyer');
      final got = await repo.watchOrders('buyer').first;
      expect(got.single.status, OrderStatus.delivered);
    });
  });

  group('live mode', () {
    test('turning demo off removes the seeded world', () async {
      final p = Phone('u1', LocalMarketRepository.memory(), demo: true);
      await settle();
      expect(p.s.products.length, greaterThan(5));
      p.store.setDemoMode(false);
      expect(p.s.demoMode, isFalse);
      expect(p.s.products, isEmpty);
      expect(p.s.orders, isEmpty);
      expect(p.s.cases, isEmpty);
      expect(p.s.farmEarned, 0);
      expect(p.s.ledger, isEmpty);
      p.store.setDemoMode(true);
      expect(p.s.products, isNotEmpty);
      expect(p.s.farmEarned, 1240);
      p.dispose();
    });
  });

  group('two phones on a shared backend', () {
    test('farmer lists, buyer orders, driver delivers, everyone is paid once', () async {
      final db = SharedMarketDb();
      final farmer = Phone('farmer', FakeSharedMarketRepository(db));
      final buyer = Phone('buyer', FakeSharedMarketRepository(db));
      final driver = Phone('driver', FakeSharedMarketRepository(db));
      final driver2 = Phone('driver2', FakeSharedMarketRepository(db));
      await settle();

      // Farmer lists produce. The buyer's phone sees it.
      farmer.store.openAndList(const Product(
          id: 'carrots',
          name: 'Carrots 5kg',
          emoji: '🥕',
          category: Category.veg,
          farm: 'Real Farm',
          km: 1,
          price: 60,
          unit: 'pack'));
      await settle();
      final seen = buyer.s.products.firstWhere((p) => p.id == 'carrots');
      expect(seen.mine, isFalse);
      expect(farmer.s.products.firstWhere((p) => p.id == 'carrots').mine, isTrue);

      // Buyer orders. It waits for the real farmer to pack it.
      buyer.store.add('carrots', 2);
      final id = buyer.store.place(PayMethod.fnbPay);
      final pin = buyer.s.pins[id]!;
      await settle();
      expect(buyer.s.orderById(id)!.status, OrderStatus.newOrder);
      // Paid money is protected from the moment of payment, even before the farmer packs.
      expect(buyer.s.escrowHeld, buyer.s.orderById(id)!.total);
      expect(farmer.s.orderById(id)!.farmIsMe, isTrue);
      expect(driver.s.orderById(id), isNull); // not an open job yet

      // The PIN itself is never in the shared document.
      final doc = db.orders[id]!;
      expect(doc.containsKey('pin'), isFalse);
      expect(doc['pinHash'], isNotNull);
      expect(doc.toString().contains(pin), isFalse);

      // Farmer packs, so it becomes an open job for drivers.
      farmer.store.packOrder(id);
      await settle();
      expect(driver.s.orderById(id)!.status, OrderStatus.findingDriver);
      expect(driver2.s.orderById(id)!.status, OrderStatus.findingDriver);

      // One driver takes it. It vanishes from the other driver's list.
      driver.store.accept(id);
      await settle();
      expect(driver.s.orderById(id)!.driverIsMe, isTrue);
      expect(buyer.s.orderById(id)!.driver, 'driver');
      expect(driver2.s.orderById(id), isNull);
      expect(driver2.s.openJobs.where((o) => o.id == id), isEmpty);
      final winner = driver;
      final loser = driver2;

      winner.store.pickedUp(id);
      await settle();
      expect(buyer.s.orderById(id)!.pickupProof, isTrue);

      // Wrong PIN fails; the buyer's PIN works.
      expect((await winner.store.checkPin(id, '0000')).delivered, isFalse);
      expect((await winner.store.checkPin(id, pin)).delivered, isTrue);
      await settle();
      expect(buyer.s.orderById(id)!.status, OrderStatus.delivered);
      expect(buyer.s.orderById(id)!.released, isFalse);

      // Buyer confirms. Each phone pays out its own role exactly once.
      buyer.store.confirmReceived(id, 5);
      await settle();
      final o = farmer.s.orderById(id)!;
      expect(o.released, isTrue);
      expect(farmer.s.farmEarned, o.mySalesNet);
      expect(farmer.s.farmEarned, 120 * 0.92); // R120 less 8%
      expect(winner.s.driverEarned, 24); // a short trip pays the R24 minimum
      expect(loser.s.driverEarned, 0);
      expect(buyer.s.escrowHeld, 0);

      // A repeated sync must not pay anyone twice.
      farmer.store.confirmReceived(id, 5);
      await settle();
      expect(farmer.s.farmEarned, 120 * 0.92);

      for (final p in [farmer, buyer, driver, driver2]) {
        p.dispose();
      }
    });

    test('a case needs two different neighbours, and one person counts once', () async {
      final db = SharedMarketDb();
      final reporter = Phone('r', FakeSharedMarketRepository(db));
      final n1 = Phone('n1', FakeSharedMarketRepository(db));
      final n2 = Phone('n2', FakeSharedMarketRepository(db));
      final fake = Phone('fake', FakeSharedMarketRepository(db));
      await settle();
      // Only verified farmers can confirm. The unverified account cannot.
      for (final p in [reporter, n1, n2]) {
        for (final step in farmerSteps) {
          p.store.completeKyc(KycRole.farmer, step.id);
        }
      }

      final id = reporter.store.submitReport('Leaf rust', '🍂', 'Hillcrest');
      await settle();
      ReportCase on(Phone p) => p.s.cases.firstWhere((c) => c.id == id);
      expect(on(n1).stage.broadcasts, isFalse);

      await settle();
      expect(fake.store.confirmCase(id), isFalse, reason: 'unverified accounts cannot confirm');
      await settle();
      expect(on(n2).confirmations, 0);
      reporter.store.confirmCase(id); // reporters cannot confirm their own
      n1.store.confirmCase(id);
      n1.store.confirmCase(id); // same person again does nothing
      await settle();
      expect(on(n2).confirmations, 1);
      expect(on(n2).stage.broadcasts, isFalse);

      n2.store.confirmCase(id);
      await settle();
      expect(on(reporter).confirmations, 2);
      expect(on(reporter).stage, ReportStage.corroborated);
      expect(on(n1).stage.broadcasts, isTrue);

      for (final p in [reporter, n1, n2, fake]) {
        p.dispose();
      }
    });

    test('a dispute freezes money on every phone and waits for a mediator', () async {
      final db = SharedMarketDb();
      final farmer = Phone('farmer', FakeSharedMarketRepository(db));
      final buyer = Phone('buyer', FakeSharedMarketRepository(db));
      final driver = Phone('driver', FakeSharedMarketRepository(db));
      await settle();
      farmer.store.openAndList(const Product(
          id: 'eggs',
          name: 'Eggs',
          emoji: '🥚',
          category: Category.dairy,
          farm: 'Real Farm',
          km: 1,
          price: 80,
          unit: 'tray'));
      await settle();
      buyer.store.add('eggs');
      final id = buyer.store.place(PayMethod.instantMoney);
      await settle();
      farmer.store.packOrder(id);
      await settle();
      driver.store.accept(id);
      await settle();
      driver.store.pickedUp(id);
      await settle();

      buyer.store.openDispute(id, DisputeReason.notDelivered, '');
      await settle();
      expect(driver.s.orderById(id)!.disputed, isTrue);
      expect(farmer.s.orderById(id)!.disputed, isTrue);
      // Live mode: nobody resolves it automatically.
      await settle(200);
      expect(buyer.s.orderById(id)!.dispute!.stage, DisputeStage.open);
      expect(farmer.s.farmEarned, 0);

      // A mediator decides: full refund. Nobody earns from it.
      buyer.store.resolveDispute(id, Outcome.fullRefund);
      await settle();
      expect(farmer.s.farmEarned, 0);
      expect(driver.s.driverEarned, 0);
      expect(buyer.s.ledger.first.kind, LedgerKind.refund);

      for (final p in [farmer, buyer, driver]) {
        p.dispose();
      }
    });
  });
}
