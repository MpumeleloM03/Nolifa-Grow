import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'open_store.dart';

class Phone {
  final ProviderContainer c;
  Phone(String uid, MarketRepository repo)
      : c = ProviderContainer(overrides: [
          marketUidProvider.overrideWithValue(uid),
          marketNameProvider.overrideWithValue(uid),
          marketRepositoryProvider.overrideWithValue(repo),
          waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        ]) {
    c.listen(marketProvider, (_, __) {});
    store.setDemoMode(false);
  }
  MarketStore get store => c.read(marketProvider.notifier);
  MarketState get s => c.read(marketProvider);
  void dispose() => c.dispose();
}

Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

void main() {
  test('a far farm: drop-off, hub check-in, release, then a driver can take it', () async {
    final db = FakeFirebaseFirestore();
    final farmer = Phone('farmer', FirestoreMarketRepository(db: db));
    final buyer = Phone('buyer', FirestoreMarketRepository(db: db));
    final hub = Phone('hub', FirestoreMarketRepository(db: db));
    final driver = Phone('driver', FirestoreMarketRepository(db: db));
    await settle();

    // A farm near Howick sells to a buyer in Umlazi, about 90 km away.
    farmer.store.updateProfile(const ProfileSettings(farmName: 'Howick Greens', address: '1 Farm Road', suburb: 'Howick'));
    farmer.store.openAndList(const Product(
        id: 'spin', name: 'Spinach', emoji: '🥬', category: Category.veg, farm: 'x', km: 1, price: 20, unit: 'bunch', stock: 40));
    buyer.store.updateProfile(const ProfileSettings(address: '5 Road', suburb: 'Umlazi'));
    await settle();

    buyer.store.add('spin', 3);
    final plan = buyer.s.deliveryPlan!;
    expect(plan.route, DeliveryRoute.hub);
    expect(plan.hub!.name, 'Durban hub');
    final id = buyer.store.place(PayMethod.fnbPay);
    await settle();
    var o = farmer.s.orderById(id)!;
    expect(o.route, 'hub');
    expect(o.hubStage, 'toHub');
    expect(o.hubCode, hubCodeFor(id));

    // Packed, but not yet at the hub: no driver can see it.
    farmer.store.packOrder(id);
    await settle();
    expect(driver.s.openJobs, isEmpty);
    expect(farmer.store.dropAtHub(id), isTrue);
    expect(buyer.store.dropAtHub(id), isFalse, reason: 'only the selling farm can say it dropped it');
    await settle();
    expect(buyer.s.orderById(id)!.hubStage, 'droppedOff');
    expect(driver.s.openJobs, isEmpty);

    // The hub desk needs the right code.
    expect(hub.store.hubReceive(id, '0000'), isFalse);
    expect(hub.store.hubRelease(id), isFalse, reason: 'cannot release what is not checked in');
    expect(hub.store.hubReceive(id, hubCodeFor(id)), isTrue);
    await settle();
    expect(buyer.s.orderById(id)!.hubStage, 'received');
    expect(driver.s.openJobs, isEmpty);
    expect(hub.store.hubRelease(id), isTrue);
    await settle();

    // Now it is a job, and the driver collects at the hub.
    final job = driver.s.openJobs.single;
    expect(job.driverPickup, 'Durban hub');
    driver.store.accept(id);
    await settle();
    expect(buyer.s.orderById(id)!.driver, 'driver');
    expect(buyer.s.orderById(id)!.atHubWork, isFalse);

    for (final p in [farmer, buyer, hub, driver]) {
      p.dispose();
    }
  });

  test('a driver cannot take a hub order that is still at the hub', () async {
    final db = FakeFirebaseFirestore();
    final farmer = Phone('farmer', FirestoreMarketRepository(db: db));
    final buyer = Phone('buyer', FirestoreMarketRepository(db: db));
    final driver = Phone('driver', FirestoreMarketRepository(db: db));
    await settle();
    farmer.store.updateProfile(const ProfileSettings(farmName: 'Howick Greens', suburb: 'Howick'));
    farmer.store.openAndList(const Product(
        id: 'spin', name: 'Spinach', emoji: '🥬', category: Category.veg, farm: 'x', km: 1, price: 20, unit: 'bunch', stock: 40));
    buyer.store.updateProfile(const ProfileSettings(suburb: 'Umlazi'));
    await settle();
    buyer.store.add('spin');
    final id = buyer.store.place(PayMethod.fnbPay);
    await settle();
    farmer.store.packOrder(id);
    await settle();
    driver.store.accept(id);
    await settle();
    expect(buyer.s.orderById(id)!.driver, isNull);
    for (final p in [farmer, buyer, driver]) {
      p.dispose();
    }
  });

  test('a nearby farm skips the hub entirely', () async {
    final db = FakeFirebaseFirestore();
    final farmer = Phone('farmer', FirestoreMarketRepository(db: db));
    final buyer = Phone('buyer', FirestoreMarketRepository(db: db));
    await settle();
    farmer.store.updateProfile(const ProfileSettings(farmName: 'Westville Veg', suburb: 'Westville'));
    farmer.store.openAndList(const Product(
        id: 'spin', name: 'Spinach', emoji: '🥬', category: Category.veg, farm: 'x', km: 1, price: 20, unit: 'bunch', stock: 40));
    buyer.store.updateProfile(const ProfileSettings(suburb: 'Umlazi'));
    await settle();
    buyer.store.add('spin');
    expect(buyer.s.deliveryPlan!.route, DeliveryRoute.local);
    final id = buyer.store.place(PayMethod.fnbPay);
    expect(buyer.s.orderById(id)!.hubStage, isNull);
    await settle();
    farmer.store.packOrder(id);
    await settle();
    expect(buyer.s.openJobs.single.driverPickup, 'Westville Veg');
    for (final p in [farmer, buyer]) {
      p.dispose();
    }
  });

  test('in the demo the pretend farm and hub move an order along by themselves', () async {
    final p = Phone('u', LocalMarketRepository.memory());
    p.store.setDemoMode(true);
    p.store.updateProfile(const ProfileSettings(suburb: 'Umlazi'));
    p.store.startNewBasket('p-eggs'); // Khumalo Poultry, Stanger area
    p.store.add('p-eggs');
    final plan = p.s.deliveryPlan!;
    final id = p.store.place(PayMethod.cash);
    final o = p.s.orderById(id)!;
    if (plan.route == DeliveryRoute.hub) {
      expect(o.hubStage, 'toHub');
      expect(p.s.openJobs.where((j) => j.id == id), isEmpty);
    }
    p.dispose();
  });

  testWidgets('the hub desk checks an order in only with the right code, then releases it', (t) async {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1206, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: [
      marketUidProvider.overrideWithValue('u'),
      marketNameProvider.overrideWithValue('u'),
      marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
      waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
    ]);
    addTearDown(c.dispose);
    final store = c.read(marketProvider.notifier);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(theme: AppTheme.build(), home: const HubDeskScreen())));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('No orders are passing through a hub right now.'), findsOneWidget);

    store.startNewBasket('p-tomato');
    final id = store.place(PayMethod.cash);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Durban hub'), findsOneWidget);
    expect(find.text('On its way from the farm'), findsOneWidget);
    // The pretend farm drops it off after 8 seconds.
    await t.pump(const Duration(seconds: 9));
    expect(find.text('Dropped off, waiting to be checked in'), findsOneWidget);
    await t.enterText(find.byType(TextField), '0000');
    await t.tap(find.text('Check in'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('That code does not match this order.'), findsOneWidget);
    await t.enterText(find.byType(TextField), hubCodeFor(id));
    await t.tap(find.text('Check in'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Checked in, ready to sort'), findsOneWidget);
    expect(c.read(marketProvider).openJobs.where((j) => j.id == id), isEmpty);
    await t.tap(find.text('Release to drivers'));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(marketProvider).openJobs.where((j) => j.id == id).length, 1);
    expect(find.text('No orders are passing through a hub right now.'), findsOneWidget);
    await t.pump(const Duration(seconds: 60));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 60));
  });
}
