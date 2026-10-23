import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'open_store.dart';

final _t0 = DateTime(2026, 10, 25, 9);

ProviderContainer _box({String uid = 'farmer', bool staff = true, bool certifier = false, DateTime Function()? clock}) {
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue(uid),
    marketNameProvider.overrideWithValue('Islilo'),
    marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
    waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
    warehouseRepositoryProvider.overrideWithValue(LocalWarehouseRepository.memory()),
    warehouseClockProvider.overrideWithValue(clock ?? () => _t0),
    hubStaffProvider.overrideWithValue(staff),
    certifierProvider.overrideWithValue(certifier),
  ]);
  addTearDown(c.dispose);
  c.listen(warehouseProvider, (_, __) {});
  c.listen(marketProvider, (_, __) {});
  return c;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 40));

Future<StockLot> _announce(ProviderContainer c,
    {String name = 'Beef mince', double qty = 40, StorageZone zone = StorageZone.chilled, int days = 5}) async {
  final lot = await c.read(warehouseProvider.notifier).announce(
        productName: name,
        category: Category.meat,
        unit: 'kg',
        qty: qty,
        zone: zone,
        useBy: _t0.add(Duration(days: days)),
        expectedAt: _t0,
      );
  await _settle();
  return lot!;
}

void main() {
  group('zones', () {
    test('a reading is fine inside the band with a degree of slack', () {
      expect(StorageZone.chilled.ok(3.9), isTrue);
      expect(StorageZone.chilled.ok(4.9), isTrue);
      expect(StorageZone.chilled.ok(5.5), isFalse);
      expect(StorageZone.frozen.ok(-18), isTrue);
      expect(StorageZone.frozen.ok(-10), isFalse);
    });

    test('meat may be chilled or frozen but never kept dry; produce is not frozen', () {
      expect(StorageZone.allowedFor(Category.meat), [StorageZone.chilled, StorageZone.frozen]);
      expect(StorageZone.allowedFor(Category.dairy), [StorageZone.chilled]);
      expect(StorageZone.allowedFor(Category.veg), isNot(contains(StorageZone.frozen)));
      expect(StorageZone.allowedFor(Category.essentials), [StorageZone.ambient]);
    });
  });

  group('depositing', () {
    test('a farm announces a deposit and it waits to be checked in', () async {
      final c = _box();
      final lot = await _announce(c);
      expect(lot.status, LotStatus.expected);
      expect(lot.tag, isNull);
      expect(lot.remaining, 0);
      expect(c.read(warehouseProvider).expected.single.productName, 'Beef mince');
    });

    test('meat cannot be announced for the dry store, and the use-by must be in the future', () async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      expect(
          await w.announce(productName: 'Mince', category: Category.meat, unit: 'kg', qty: 5, zone: StorageZone.ambient, useBy: _t0.add(const Duration(days: 3)), expectedAt: _t0),
          isNull);
      expect(
          await w.announce(productName: 'Mince', category: Category.meat, unit: 'kg', qty: 5, zone: StorageZone.chilled, useBy: _t0.subtract(const Duration(days: 1)), expectedAt: _t0),
          isNull);
      expect(
          await w.announce(productName: 'Mince', category: Category.meat, unit: 'kg', qty: 0, zone: StorageZone.chilled, useBy: _t0.add(const Duration(days: 3)), expectedAt: _t0),
          isNull);
    });

    test('a farm sees only its own deposits', () async {
      final c = _box();
      await _announce(c);
      final s = c.read(warehouseProvider);
      expect(s.forFarmer('farmer').length, 1);
      expect(s.forFarmer('someone-else'), isEmpty);
    });
  });

  group('checking in', () {
    test('staff accept goods that arrive cold, and the lot gets a tag, a bay and a log', () async {
      final c = _box();
      final lot = await _announce(c);
      final r = await c.read(warehouseProvider.notifier).receive(lot.id, qty: 38.5, tempC: 2.8);
      await _settle();
      expect(r, isNull);
      final stored = c.read(warehouseProvider).lots.single;
      expect(stored.status, LotStatus.stored);
      expect(stored.tag, 'NLF-DBN-0001');
      expect(stored.bay, 'C1-01');
      expect(stored.qty, 38.5);
      expect(stored.remaining, 38.5);
      expect(stored.receivedTempC, 2.8);
      expect(stored.events.length, 2);
      expect(stored.events.last.text, contains('NLF-DBN-0001'));
    });

    test('goods that arrive warm are turned away with the reason', () async {
      final c = _box();
      final lot = await _announce(c);
      final r = await c.read(warehouseProvider.notifier).receive(lot.id, qty: 40, tempC: 9.5);
      await _settle();
      expect(r, contains('9.5 C'));
      expect(r, contains('0 to 4 C'));
      final l = c.read(warehouseProvider).lots.single;
      expect(l.status, LotStatus.rejected);
      expect(l.tag, isNull);
      expect(l.remaining, 0);
      expect(c.read(warehouseProvider).stored, isEmpty);
    });

    test('frozen goods are judged against the freezer, not the fridge', () async {
      final c = _box();
      final lot = await _announce(c, name: 'Brisket', zone: StorageZone.frozen);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 10, tempC: -4), isNotNull);
      final lot2 = await _announce(c, name: 'Brisket', zone: StorageZone.frozen);
      expect(await c.read(warehouseProvider.notifier).receive(lot2.id, qty: 10, tempC: -19), isNull);
    });

    test('tags count up and bays fill in order per room', () async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      for (var i = 0; i < 3; i++) {
        final l = await _announce(c, name: 'Item $i');
        await w.receive(l.id, qty: 5, tempC: 2);
        await _settle();
      }
      final tags = c.read(warehouseProvider).stored.map((l) => l.tag).toSet();
      expect(tags, {'NLF-DBN-0001', 'NLF-DBN-0002', 'NLF-DBN-0003'});
      final bays = c.read(warehouseProvider).stored.map((l) => l.bay).toSet();
      expect(bays, {'C1-01', 'C1-02', 'C1-03'});
    });

    test('only warehouse staff can check goods in', () async {
      final c = _box(staff: false);
      c.read(marketProvider.notifier).setDemoMode(false); // in the demo anyone can run the desk
      final lot = await _announce(c);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 5, tempC: 2), contains('Only warehouse staff'));
      expect(await c.read(warehouseProvider.notifier).reject(lot.id, 'x'), isFalse);
    });

    test('a lot cannot be checked in twice', () async {
      final c = _box();
      final lot = await _announce(c);
      final w = c.read(warehouseProvider.notifier);
      await w.receive(lot.id, qty: 5, tempC: 2);
      await _settle();
      expect(await w.receive(lot.id, qty: 5, tempC: 2), contains('not waiting'));
    });
  });

  group('picking for orders', () {
    Future<ProviderContainer> stocked() async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      // Two lots of the same product; the one that expires first must go first.
      final late = await _announce(c, qty: 30, days: 9);
      await w.receive(late.id, qty: 30, tempC: 2);
      await _settle();
      final early = await _announce(c, qty: 10, days: 3);
      await w.receive(early.id, qty: 10, tempC: 2);
      await _settle();
      return c;
    }

    test('goods that expire first are picked first, across lots', () async {
      final c = await stocked();
      final picks = await c.read(warehouseProvider.notifier).dispatch('Islilo', 'beef mince', 14, 'UD-1');
      await _settle();
      // The farm name is the profile farm name, which is empty here, so it falls back to the account name.
      expect(picks, isNotNull);
      expect(picks!.length, 2);
      expect(picks.first.qty, 10);
      expect(picks.last.qty, 4);
      final s = c.read(warehouseProvider);
      expect(s.available('Islilo', 'Beef mince'), 26);
      final emptied = s.lots.firstWhere((l) => l.id == picks.first.lotId);
      expect(emptied.status, LotStatus.emptied);
      expect(emptied.events.last.text, contains('UD-1'));
    });

    test('asking for more than there is takes nothing', () async {
      final c = await stocked();
      expect(await c.read(warehouseProvider.notifier).dispatch('Islilo', 'Beef mince', 100, 'UD-2'), isNull);
      expect(c.read(warehouseProvider).available('Islilo', 'Beef mince'), 40);
    });

    test('a room that is too warm holds its goods back', () async {
      final c = await stocked();
      final w = c.read(warehouseProvider.notifier);
      await w.logTemp('Durban hub', StorageZone.chilled, 11);
      await _settle();
      expect(c.read(warehouseProvider).zoneAtRisk('Durban hub', StorageZone.chilled), isTrue);
      expect(await w.dispatch('Islilo', 'Beef mince', 5, 'UD-3'), isNull);
      await w.logTemp('Durban hub', StorageZone.chilled, 2);
      await _settle();
      expect(await w.dispatch('Islilo', 'Beef mince', 5, 'UD-3'), isNotNull);
    });

    test('goods past their use-by date are written off, not sold', () async {
      var now = _t0;
      final c = _box(clock: () => now);
      final w = c.read(warehouseProvider.notifier);
      final lot = await _announce(c, days: 2);
      await w.receive(lot.id, qty: 10, tempC: 2);
      await _settle();
      now = _t0.add(const Duration(days: 4));
      expect(await w.writeOffExpired(), 1);
      await _settle();
      final l = c.read(warehouseProvider).lots.single;
      expect(l.status, LotStatus.expired);
      expect(c.read(warehouseProvider).available('Islilo', 'Beef mince'), 0);
    });
  });

  group('sensors', () {
    test('the pretend sensors keep every room in range', () async {
      final c = _box();
      await c.read(warehouseProvider.notifier).simulateSensors();
      await _settle();
      final s = c.read(warehouseProvider);
      for (final z in StorageZone.values) {
        expect(s.latest('Durban hub', z), isNotNull);
        expect(s.zoneAtRisk('Durban hub', z), isFalse, reason: z.name);
      }
    });
  });

  group('the demo butchery and the order flow', () {
    test('demo stock is tagged and cold, and a hub order from it skips the farm drop-off', () async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      await w.seedDemoIfEmpty();
      await w.seedDemoIfEmpty(); // twice does not double it
      await _settle();
      final s = c.read(warehouseProvider);
      expect(s.stored.length, 6);
      expect(s.stored.every((l) => l.tag!.startsWith('NLF-DBN-')), isTrue);
      expect(s.available('Fatboy Butcheries', 'Beef mince'), 40);

      final m = c.read(marketProvider.notifier);
      m.setDemoMode(true);
      m.startNewBasket('p-fb-beef-mince');
      m.add('p-fb-beef-mince', 2);
      final plan = c.read(marketProvider).deliveryPlan!;
      expect(plan.route, DeliveryRoute.hub);
      expect(plan.hub!.name, 'Durban hub');
      final id = m.place(PayMethod.cash, fromStock: true);
      final o = c.read(marketProvider).orderById(id)!;
      expect(o.fromStock, isTrue);
      expect(o.hubStage, 'received');
      expect(o.pickup, 'Fatboy Butcheries');
      expect(c.read(marketProvider).openJobs.where((j) => j.id == id), isEmpty);

      final picks = await w.dispatch(o.pickup, 'Beef mince', 2, id);
      expect(picks!.single.tag, startsWith('NLF-DBN-'));
      expect(m.hubRelease(id), isTrue);
      expect(c.read(marketProvider).openJobs.where((j) => j.id == id).length, 1);
      await _settle();
      expect(c.read(warehouseProvider).available('Fatboy Butcheries', 'Beef mince'), 38);
    });

    test('the catalogue has the real butchery products with their shop prices', () {
      final c = _box();
      final p = c.read(marketProvider).products.where((p) => p.farm == 'Fatboy Butcheries').toList();
      expect(p.length, 10);
      expect(p.every((x) => x.category == Category.meat), isTrue);
      expect(p.firstWhere((x) => x.name == 'Beef fillet').price, 300);
      expect(p.firstWhere((x) => x.name == 'Chicken breast').price, 65);
    });
  });

  group('staff tools', () {
    test('staff can find a lot by its tag, move it and write some off with a reason', () async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      final lot = await _announce(c, qty: 20);
      await w.receive(lot.id, qty: 20, tempC: 2);
      await _settle();
      expect(w.lotByCode('nlf-dbn-0001')!.id, lot.id);
      expect(w.lotByCode(lot.id)!.tag, 'NLF-DBN-0001');
      expect(w.lotByCode('nope'), isNull);
      expect(await w.moveLot(lot.id, 'C2-07'), isTrue);
      await _settle();
      expect(c.read(warehouseProvider).lots.single.bay, 'C2-07');
      expect(await w.writeOffQty(lot.id, 3.5, ''), isFalse, reason: 'a reason is required');
      expect(await w.writeOffQty(lot.id, 99, 'Dropped'), isFalse);
      expect(await w.writeOffQty(lot.id, 3.5, 'Packaging split'), isTrue);
      await _settle();
      final l = c.read(warehouseProvider).lots.single;
      expect(l.remaining, 16.5);
      expect(l.events.last.text, contains('Packaging split'));
    });

    test('lots for a product come oldest first', () async {
      final c = _box();
      final w = c.read(warehouseProvider.notifier);
      for (final d in [9, 3, 6]) {
        final l = await _announce(c, qty: 5, days: d);
        await w.receive(l.id, qty: 5, tempC: 2);
        await _settle();
      }
      final order = w.lotsFor('Islilo', 'Beef mince').map((l) => l.daysLeft(_t0)).toList();
      expect(order, [3, 6, 9]);
    });
  });

  group('certification', () {
    ProviderContainer live({bool certifier = true, DateTime Function()? clock}) {
      final c = _box(certifier: certifier, clock: clock);
      c.read(marketProvider.notifier).setDemoMode(false);
      return c;
    }

    Future<WarehouseCert?> certify(ProviderContainer c, {List<StorageZone>? rooms, List<String>? checks, int days = 365}) =>
        c.read(warehouseProvider.notifier).certify(
              hub: 'Durban hub',
              certifierName: 'T. Naidoo',
              organisation: 'KZN Food Safety Inspectors',
              certNumber: 'FS-2026-0042',
              rooms: rooms ?? [StorageZone.chilled, StorageZone.frozen],
              checksPassed: checks ?? certChecks,
              validDays: days,
            );

    test('an uncertified room cannot take goods in a live warehouse', () async {
      final c = live();
      final lot = await _announce(c);
      final r = await c.read(warehouseProvider.notifier).receive(lot.id, qty: 10, tempC: 2);
      expect(r, contains('No valid certificate'));
      expect(c.read(warehouseProvider).lots.single.status, LotStatus.expected);
    });

    test('a certifier certifies the rooms and then goods can be checked in', () async {
      final c = live();
      final cert = await certify(c);
      await _settle();
      expect(cert, isNotNull);
      expect(c.read(warehouseProvider).certifiedRooms('Durban hub', _t0), {StorageZone.chilled, StorageZone.frozen});
      final lot = await _announce(c);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 10, tempC: 2), isNull);
    });

    test('only the rooms named on the certificate may be used', () async {
      final c = live();
      await certify(c, rooms: [StorageZone.chilled]);
      await _settle();
      final lot = await _announce(c, name: 'Brisket', zone: StorageZone.frozen);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 10, tempC: -19), contains('frozen room'));
    });

    test('everyone but a certifier is refused, and every check must pass', () async {
      expect(await certify(live(certifier: false)), isNull);
      final c = live();
      expect(await certify(c, checks: certChecks.take(3).toList()), isNull);
      expect(await certify(c, rooms: const []), isNull);
      expect(c.read(warehouseProvider).certs, isEmpty);
    });

    test('a certificate runs out', () async {
      var now = _t0;
      final c = live(clock: () => now);
      await certify(c, days: 30);
      await _settle();
      final lot = await _announce(c);
      now = _t0.add(const Duration(days: 31));
      expect(c.read(warehouseProvider).certifiedRooms('Durban hub', now), isEmpty);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 5, tempC: 2), contains('No valid certificate'));
    });

    test('the demo warehouse needs no certificate so it can be shown', () async {
      final c = _box();
      final lot = await _announce(c);
      expect(await c.read(warehouseProvider.notifier).receive(lot.id, qty: 5, tempC: 2), isNull);
    });
  });

  group('Islilo Farming quick start', () {
    test('a farm that cannot sell yet cannot list the range, and one that can gets ten products', () {
      final c = _box();
      final m = c.read(marketProvider.notifier);
      m.setDemoMode(false);
      expect(m.listRange(fatboyRange), contains('Finish the steps'));
      expect(c.read(marketProvider).products.where((p) => p.mine), isEmpty);

      m.updateProfile(const ProfileSettings(farmName: 'Fatboy Butcheries', suburb: 'uMhlanga'));
      m.openForSelling();
      expect(m.listRange(fatboyRange, stock: 25), isNull);
      final mine = c.read(marketProvider).products.where((p) => p.mine).toList();
      expect(mine.length, 10);
      expect(mine.every((p) => p.farm == 'Fatboy Butcheries' && p.stock == 25 && p.category == Category.meat), isTrue);
      expect(mine.every((p) => p.place == 'uMhlanga'), isTrue);
    });
  });

  group('screens', () {
    Future<ProviderContainer> mount(WidgetTester t, Widget page, {bool staff = true}) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = const Size(1206, 4000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('farmer'),
        marketNameProvider.overrideWithValue('Islilo'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        warehouseRepositoryProvider.overrideWithValue(LocalWarehouseRepository.memory()),
        hubStaffProvider.overrideWithValue(staff),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(theme: AppTheme.build(), home: page)));
      await t.pump(const Duration(milliseconds: 400));
      return c;
    }

    testWidgets('the farm deposits goods, the desk checks them in cold, and the farm sees the tag', (t) async {
      final c = await mount(t, const FarmerWarehouseScreen());
      expect(find.text('Nothing deposited yet.'), findsOneWidget);
      await t.tap(find.text('Deposit goods').first);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.enterText(find.widgetWithText(TextFormField, 'Product (for example Beef mince)'), 'Beef mince');
      await t.enterText(find.widgetWithText(TextFormField, 'How much (kg or units)'), '25');
      await t.tap(find.text('Tell the warehouse'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('No tag yet'), findsOneWidget);
      final lot = c.read(warehouseProvider).lots.single;
      expect(lot.farmerId, 'farmer');
      expect(lot.zone, StorageZone.chilled);

      await c.read(warehouseProvider.notifier).receive(lot.id, qty: 24.5, tempC: 3);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('NLF-DBN-0001'), findsOneWidget);
      expect(find.text('In storage'), findsWidgets);
      expect(find.textContaining('24.5 of 24.5'), findsOneWidget);
      expect(find.textContaining('In at 3.0 C'), findsOneWidget);
    });

    testWidgets('the desk turns away a warm delivery and says why', (t) async {
      final c = await mount(t, const WarehouseDeskScreen());
      await _announceIn(c);
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.widgetWithText(TextField, 'Temp (C)'), '8.2');
      await t.tap(find.text('Check in'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Arrived at 8.2 C'), findsWidgets);
      expect(c.read(warehouseProvider).lots.firstWhere((l) => l.farmerId == 'farmer').status, LotStatus.rejected);
    });
  });
}

Future<void> _announceIn(ProviderContainer c) async {
  await c.read(warehouseProvider.notifier).announce(
        productName: 'Chicken breast',
        category: Category.meat,
        unit: 'kg',
        qty: 12,
        zone: StorageZone.chilled,
        useBy: DateTime.now().add(const Duration(days: 4)),
        expectedAt: DateTime.now(),
      );
}
