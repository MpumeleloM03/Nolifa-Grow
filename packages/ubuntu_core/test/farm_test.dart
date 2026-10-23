import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'open_store.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

class Phone {
  final ProviderContainer c;
  final String uid;
  Phone(this.uid, MarketRepository repo, {bool demo = false})
      : c = ProviderContainer(overrides: [
          marketUidProvider.overrideWithValue(uid),
          marketNameProvider.overrideWithValue(uid),
          marketRepositoryProvider.overrideWithValue(repo),
          waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        ]) {
    c.listen(marketProvider, (_, __) {});
    if (!demo) store.setDemoMode(false);
  }

  MarketStore get store => c.read(marketProvider.notifier);
  MarketState get s => c.read(marketProvider);
  void dispose() => c.dispose();
}

Future<void> settle([int ms = 60]) async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms));
  }
}

void main() {
  group('farms', () {
    test('the catalogue becomes farms, nearest first', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      final farms = p.s.farms;
      expect(farms.map((f) => f.name).first, 'Nolifa Depot');
      expect(farms.length, 8);
      expect(farms.map((f) => f.km).toList(), [...farms.map((f) => f.km)]..sort());
      final mkhize = farms.firstWhere((f) => f.name == 'Mkhize Family Farm');
      expect(mkhize.products.length, 3);
      expect(mkhize.delivery, DeliveryMode.self);
      expect(mkhize.deliveryLabel, 'Farm delivers · R15');
      expect(farms.firstWhere((f) => f.name == 'Khumalo Poultry').deliveryLabel, 'Farm delivers · free');
      expect(farms.firstWhere((f) => f.name == 'Dlamini Mill').deliveryLabel, 'Nolifa Delivery · R25');
      expect(mkhize.rating, 4.8);
      p.dispose();
    });

    test('search matches a farm or one of its products, and categories filter farms', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      expect(groupFarms(p.s.products, query: 'egg').single.name, 'Khumalo Poultry');
      expect(groupFarms(p.s.products, query: 'mkhize').single.name, 'Mkhize Family Farm');
      expect(groupFarms(p.s.products, query: 'zzz'), isEmpty);
      expect(groupFarms(p.s.products, category: Category.fruit).single.name, 'Naidoo Orchards');
      p.dispose();
    });

    test('paused products disappear from the farm, and an empty farm disappears', () {
      final products = [
        const Product(
            id: 'a',
            name: 'A',
            emoji: '🥕',
            category: Category.veg,
            farm: 'F',
            km: 1,
            price: 10,
            unit: 'x',
            available: false),
      ];
      expect(groupFarms(products), isEmpty);
    });

    test('a real farm appears with defaults until it has a track record', () {
      const p = Product(
          id: 'a',
          name: 'Beans',
          emoji: '🫘',
          category: Category.grain,
          farm: "Thandi's Farm",
          km: 3,
          price: 10,
          unit: 'x',
          ownerId: 'u1');
      final f = groupFarms([p]).single;
      expect(f.rating, isNull);
      expect(f.tagline, 'Fresh from the farm');
      expect(f.etaMinutes, 45);
      expect(f.verified, isTrue);
    });
  });

  group('the basket holds one farm at a time', () {
    test('another farm is refused until a new basket is started', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      expect(p.store.add('p-spinach'), isTrue);
      expect(p.store.add('p-carrot'), isTrue); // same farm
      expect(p.store.add('p-tomato'), isFalse); // different farm
      expect(p.s.cart, {'p-spinach': 1, 'p-carrot': 1});
      expect(p.s.cartFarm, 'Mkhize Family Farm');

      p.store.startNewBasket('p-tomato');
      expect(p.s.cart, {'p-tomato': 1});
      expect(p.s.cartFarm, 'Sithole Growers');
      p.dispose();
    });

    test('the delivery fee follows how the farm delivers', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.add('p-spinach');
      expect(p.s.deliveryFee, 15); // Mkhize delivers itself for R15
      expect(p.s.cartSelfDelivery, isTrue);
      p.store.startNewBasket('p-eggs');
      expect(p.s.deliveryFee, 0); // Khumalo delivers free
      p.store.startNewBasket('p-tomato');
      expect(p.s.deliveryFee, 35); // Nolifa Delivery, through a hub because Sithole is far from Umlazi
      expect(p.s.cartSelfDelivery, isFalse);
      p.dispose();
    });

    test('a sold-out product cannot be added', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.setDemoMode(false);
      p.store.openAndList(const Product(
          id: 'x',
          name: 'X',
          emoji: '🥕',
          category: Category.veg,
          farm: 'ignored',
          km: 1,
          price: 5,
          unit: 'u',
          stock: 0));
      expect(p.store.add('x'), isFalse);
      p.dispose();
    });
  });

  group('profile and business', () {
    test('a farm must register, verify and pay before it can sell', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.setDemoMode(false);
      expect(p.s.canSell, isFalse);
      p.store.registerBusiness(kind: 'cooperative', regNumber: 'K2026/1');
      expect(p.s.business.registered, isTrue);
      expect(p.s.business.kind, 'cooperative');
      expect(p.s.canSell, isFalse); // not verified, not paid

      for (final step in farmerSteps) {
        p.store.completeKyc(KycRole.farmer, step.id);
      }
      expect(p.s.canSell, isFalse); // still not paid

      p.store.setPlan(Plan.grow);
      expect(p.s.business.planPaid, isTrue);
      expect(p.s.canSell, isFalse); // land and crops not shown yet

      p.store.submitLandEvidence();
      expect(p.s.canSell, isTrue);
      expect(p.s.ledger.first.title, 'Grow plan');
      expect(p.s.ledger.first.amount, -99);
      p.dispose();
    });

    test('before the inspection a farm sells fresh produce with limits; eggs and milk wait', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.setDemoMode(false);
      p.store.registerBusiness();
      for (final step in farmerSteps) {
        p.store.completeKyc(KycRole.farmer, step.id);
      }
      p.store.setPlan(Plan.starter);
      p.store.submitLandEvidence();
      expect(p.s.provisionalActive, isTrue);
      expect(p.s.inspectionPassed, isFalse);
      expect(p.s.provisionalRoom, Inspection.provisionalCap);
      expect(p.s.listBlock(Category.veg), isNull);
      expect(p.s.listBlock(Category.fruit), isNull);
      expect(p.s.listBlock(Category.dairy), contains('inspection'));

      p.store.requestInspection(InspectionRoute.extensionOfficer);
      expect(p.s.business.inspection, InspectionStatus.scheduled);
      expect(p.s.business.visitOn, isNotNull);
      expect(p.s.listBlock(Category.dairy), isNotNull, reason: 'booked is not passed');

      p.store.recordInspection(passed: true);
      expect(p.s.inspectionPassed, isTrue);
      expect(p.s.listBlock(Category.dairy), isNull);
      expect(p.s.provisionalRoom, double.infinity);
      p.dispose();
    });

    test('a failed inspection pauses selling until a new one passes', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.setDemoMode(false);
      p.store.registerBusiness();
      for (final step in farmerSteps) {
        p.store.completeKyc(KycRole.farmer, step.id);
      }
      p.store.setPlan(Plan.starter);
      p.store.submitLandEvidence();
      p.store.requestInspection(InspectionRoute.surveyor);
      p.store.recordInspection(passed: false);
      expect(p.s.canSell, isFalse);
      p.store.requestInspection(InspectionRoute.coopDay);
      p.store.recordInspection(passed: true);
      expect(p.s.canSell, isTrue);
      p.dispose();
    });

    test('inspection state survives a restart', () async {
      final kv = MemoryKv();
      final a = Phone('u', LocalMarketRepository(kv), demo: true);
      await settle();
      a.store.submitLandEvidence();
      a.store.requestInspection(InspectionRoute.coopDay);
      await settle();
      a.dispose();
      final b = Phone('u', LocalMarketRepository(kv), demo: true);
      await settle();
      expect(b.s.business.evidenceDone, isTrue);
      expect(b.s.business.route, InspectionRoute.coopDay);
      expect(b.s.business.inspection, InspectionStatus.scheduled);
      b.dispose();
    });

    test('farm name and delivery follow the farm onto every product', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.setDemoMode(false);
      const base = Product(
          id: 'p1',
          name: 'Carrots',
          emoji: '🥕',
          category: Category.veg,
          farm: 'x',
          km: 1,
          price: 20,
          unit: 'bag',
          stock: 10);
      p.store.openAndList(base);
      expect(p.s.products.single.farm, "u's Farm");
      expect(p.s.products.single.delivery, DeliveryMode.platform);

      p.store.updateProfile(const ProfileSettings(
          farmName: 'Green Hills',
          delivery: DeliveryMode.self,
          deliveryFee: 12));
      expect(p.s.products.single.farm, 'Green Hills');
      expect(p.s.products.single.delivery, DeliveryMode.self);
      expect(p.s.products.single.deliveryFee, 12);

      // New listings pick up the same details.
      p.store.openAndList(base.copyWith(farm: 'wrong'));
      expect(p.s.products.every((x) => x.farm == 'Green Hills'), isTrue);
      p.dispose();
    });

    test('the saved name and address go onto orders', () {
      final p = Phone('u', LocalMarketRepository.memory(), demo: true);
      p.store.updateProfile(const ProfileSettings(
          name: 'Thandi Nkosi', address: '12 Jabu Rd', suburb: 'Umlazi'));
      expect(p.s.profile.addressLine, '12 Jabu Rd, Umlazi');
      p.store.add('p-water');
      final id = p.store.place(PayMethod.fnbPay);
      final o = p.s.orderById(id)!;
      expect(o.customer, 'Thandi');
      expect(o.dropArea, '12 Jabu Rd, Umlazi');
      p.dispose();
    });

    test('profile and business survive a restart', () async {
      final kv = MemoryKv();
      final a = Phone('u', LocalMarketRepository(kv), demo: true);
      await settle();
      a.store.updateProfile(const ProfileSettings(
          name: 'Thandi', phone: '0821234567', notifyWater: false));
      a.store.registerBusiness();
      await settle();
      a.dispose();
      final b = Phone('u', LocalMarketRepository(kv), demo: true);
      await settle();
      expect(b.s.profile.phone, '0821234567');
      expect(b.s.profile.notifyWater, isFalse);
      expect(b.s.business.registered, isTrue);
      b.dispose();
    });
  });

  group('a farm that delivers itself', () {
    testWidgets('a demo farm sends its own person and keeps the delivery fee out of Nolifa Delivery',
        (t) async {
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u'),
        marketNameProvider.overrideWithValue('u'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
      ]);
      addTearDown(c.dispose);
      c.listen(marketProvider, (_, __) {});
      final store = c.read(marketProvider.notifier);
      await t.pump(const Duration(milliseconds: 100));

      store.add('p-spinach', 2);
      final id = store.place(PayMethod.fnbPay);
      var o = c.read(marketProvider).orderById(id)!;
      expect(o.selfDelivery, isTrue);
      expect(o.deliveryFee, 15);
      expect(o.driverPay, 0); // no Nolifa driver is paid
      expect(o.platformTake, o.serviceFee + r2(o.subtotal * o.commission));

      await t.pump(const Duration(seconds: 6));
      o = c.read(marketProvider).orderById(id)!;
      expect(o.driver, 'Mkhize Family Farm'); // the farm's own person
      await t.pump(const Duration(seconds: 20));
      expect(c.read(marketProvider).orderById(id)!.status, OrderStatus.delivered);
      store.confirmReceived(id, 5);
      await t.pump(const Duration(seconds: 1));
      expect(c.read(marketProvider).orderById(id)!.released, isTrue);
      expect(c.read(marketProvider).driverEarned, 310); // unchanged
      await t.pump(const Duration(seconds: 30));
    });

    test('a real farm collects its own order, delivers with the PIN and keeps the fee', () async {
      final db = FakeFirebaseFirestore();
      final farmer = Phone('farmer', FirestoreMarketRepository(db: db));
      final buyer = Phone('buyer', FirestoreMarketRepository(db: db));
      await settle();

      farmer.store.updateProfile(const ProfileSettings(
          farmName: 'Green Hills', delivery: DeliveryMode.self, deliveryFee: 10));
      farmer.store.openAndList(const Product(
          id: 'carrots',
          name: 'Carrots',
          emoji: '🥕',
          category: Category.veg,
          farm: 'x',
          km: 1,
          price: 60,
          unit: 'bag',
          stock: 20));
      await settle();

      expect(buyer.s.farms.single.name, 'Green Hills');
      buyer.store.add('carrots', 2);
      expect(buyer.s.deliveryFee, 10);
      final id = buyer.store.place(PayMethod.fnbPay);
      final pin = buyer.s.pins[id]!;
      await settle();
      expect(farmer.s.orderById(id)!.selfDelivery, isTrue);
      expect(farmer.s.products.single.stock, 18); // two came off the shelf

      // Packing it makes the farmer the driver: no open job for anyone else.
      farmer.store.packOrder(id);
      await settle();
      var o = farmer.s.orderById(id)!;
      expect(o.status, OrderStatus.assigned);
      expect(o.driverIsMe, isTrue);
      expect(o.driver, 'Green Hills');
      expect(buyer.s.orderById(id)!.driver, 'Green Hills');
      expect(farmer.s.openJobs.where((j) => j.id == id), isEmpty);

      farmer.store.pickedUp(id);
      await settle();
      expect(farmer.store.deliverWithPin(id, '0000'), isFalse);
      expect(farmer.store.deliverWithPin(id, pin), isTrue);
      await settle();
      buyer.store.confirmReceived(id, 5);
      await settle();

      o = farmer.s.orderById(id)!;
      expect(o.released, isTrue);
      // R120 less 8% = R110.40, plus the R10 delivery fee the farm kept.
      expect(farmer.s.farmEarned, 120.4);
      expect(farmer.s.driverEarned, 0);
      expect(farmer.s.ledger.any((e) => e.title == 'Delivery by you'), isTrue);

      farmer.dispose();
      buyer.dispose();
    });
  });
}
