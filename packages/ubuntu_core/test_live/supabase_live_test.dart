// Runs the real Supabase repositories against a real database: several people
// signed in at once, each with their own row level security.
//
//   supabase start
//   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=... SUPABASE_SERVICE_KEY=... \
//     flutter test test_live
//
// Skipped when the variables are not set, so the normal suite stays offline.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

final _url = Platform.environment['SUPABASE_URL'] ?? '';
final _anon = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
final _service = Platform.environment['SUPABASE_SERVICE_KEY'] ?? '';
final _run = DateTime.now().millisecondsSinceEpoch;

class Person {
  Person(this.name, this.client, this.id);
  final String name;
  final SupabaseClient client;
  final String id;
  SupabaseMarketRepository get market => SupabaseMarketRepository(db: client);
  SupabaseWaterRepository get water => SupabaseWaterRepository(db: client);
  SupabaseRoadRepository get roads => SupabaseRoadRepository(db: client);
  SupabaseWarehouseRepository get warehouse => SupabaseWarehouseRepository(db: client);
}

Future<Person> signUp(String name) async {
  final c = SupabaseClient(_url, _anon, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  final res = await c.auth.signUp(email: '$name-$_run@example.com', password: 'test-pass-123', data: {'name': name});
  return Person(name, c, res.user!.id);
}

Future<Person> signIn(Person p) async {
  final c = SupabaseClient(_url, _anon, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  await c.auth.signInWithPassword(email: '${p.name}-$_run@example.com', password: 'test-pass-123');
  return Person(p.name, c, p.id);
}

Order newOrder(String id, String buyer, String farmer, {String route = 'local', String? hubStage}) => Order(
      id: id,
      lines: const [OrderLine('Carrots', '🥕', 2, 60)],
      deliveryFee: 25,
      serviceFee: 5,
      method: PayMethod.fnbPay,
      status: OrderStatus.newOrder,
      customer: 'Buyer',
      pickup: 'Farm',
      dropArea: 'Street',
      pin: '4321',
      placed: DateTime.now(),
      customerId: buyer,
      farmerId: farmer,
      route: route,
      hubStage: hubStage,
    );

void main() {
  final skip = (_url.isEmpty || _anon.isEmpty || _service.isEmpty)
      ? 'set SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_KEY to run'
      : null;

  group('real database', () {
    late SupabaseClient admin;
    late Person farmer, buyer, d1, d2, hub, utility, resident;

    setUpAll(() async {
      admin = SupabaseClient(_url, _service);
      farmer = await signUp('farmer');
      buyer = await signUp('buyer');
      d1 = await signUp('driver1');
      d2 = await signUp('driver2');
      hub = await signUp('hub');
      utility = await signUp('utility');
      resident = await signUp('resident');
      await admin.from('verified_users').insert([
        for (final p in [farmer, buyer, d1, d2, resident]) {'uid': p.id}
      ]);
      await admin.from('staff').insert({'uid': hub.id, 'name': 'Hub desk'});
      await admin.auth.admin.updateUserById(utility.id, attributes: AdminUserAttributes(appMetadata: {'utility': true}));
      utility = await signIn(utility); // the new claim arrives with a fresh token
    });

    test('market: list, order, pack, one driver wins, deliver, pay', () async {
      await farmer.market.putProduct(
          Product(
              id: 'live-carrots-$_run', name: 'Carrots', emoji: '🥕', category: Category.veg, farm: 'Live Farm', km: 1, price: 60, unit: 'bag', stock: 10),
          farmer.id);
      final seen = await buyer.market.watchProducts(buyer.id).first;
      expect(seen.map((p) => p.id), contains('live-carrots-$_run'));

      final o = newOrder('UD-LIVE-$_run', buyer.id, farmer.id);
      await buyer.market.putOrder(o, buyer.id);
      final farmerView = await farmer.market.watchOrders(farmer.id).first;
      expect(farmerView.map((x) => x.id), contains(o.id));
      expect((await d1.market.watchOrders(d1.id).first).where((x) => x.id == o.id), isEmpty, reason: 'not packed yet');

      await farmer.market.putOrder(o.copyWith(status: OrderStatus.findingDriver, rev: 1), farmer.id);
      expect((await d1.market.watchOrders(d1.id).first).map((x) => x.id), contains(o.id));

      expect(await d1.market.claimJob(o.id, d1.id, 'One'), isTrue);
      expect(await d2.market.claimJob(o.id, d2.id, 'Two'), isFalse);
      final mine = (await d1.market.watchOrders(d1.id).first).firstWhere((x) => x.id == o.id);
      expect(mine.driverIsMe, isTrue);

      await d1.market.putOrder(mine.copyWith(status: OrderStatus.pickedUp, pickupProof: true, rev: mine.rev + 1), d1.id);
      final picked = (await d1.market.watchOrders(d1.id).first).firstWhere((x) => x.id == o.id);
      await d1.market.putOrder(picked.copyWith(status: OrderStatus.delivered, deliveredAt: DateTime.now(), rev: picked.rev + 1), d1.id);
      final delivered = (await buyer.market.watchOrders(buyer.id).first).firstWhere((x) => x.id == o.id);
      expect(delivered.status, OrderStatus.delivered);

      await buyer.market.putOrder(delivered.copyWith(released: true, rating: 5, rev: delivered.rev + 1), buyer.id);
      final paid = (await buyer.market.watchOrders(buyer.id).first).firstWhere((x) => x.id == o.id);
      expect(paid.released, isTrue);
      expect((await resident.market.watchOrders(resident.id).first).where((x) => x.id == o.id), isEmpty, reason: 'strangers see nothing');
    });

    test('market: money and states are protected', () async {
      final o = newOrder('UD-LIVE-M-$_run', buyer.id, farmer.id);
      await buyer.market.putOrder(o, buyer.id);
      // The buyer tries to make it cheaper after the fact.
      await expectLater(
          buyer.client.rpc('put_order', params: {'p_data': {...orderToJson(o.copyWith(rev: 1), buyer.id), 'deliveryFee': 1}}),
          throwsA(isA<PostgrestException>()));
      // A buyer cannot mark their own order delivered.
      await expectLater(buyer.market.putOrder(o.copyWith(status: OrderStatus.delivered, rev: 2), buyer.id), throwsA(isA<PostgrestException>()));
      // The wrong person cannot order as someone else.
      await expectLater(resident.market.putOrder(newOrder('UD-LIVE-X-$_run', buyer.id, farmer.id), buyer.id),
          throwsA(isA<PostgrestException>()));
    });

    test('hub: farm drops off, staff check in and release, then a driver can take it', () async {
      final o = newOrder('UD-LIVE-H-$_run', buyer.id, farmer.id, route: 'hub', hubStage: 'toHub');
      await buyer.market.putOrder(o, buyer.id);
      await farmer.market.putOrder(o.copyWith(status: OrderStatus.findingDriver, rev: 1), farmer.id);
      expect(await d1.market.claimJob(o.id, d1.id, 'One'), isFalse, reason: 'still at the hub');
      await farmer.client.rpc('set_hub_stage', params: {'p_id': o.id, 'p_stage': 'droppedOff'});
      await expectLater(
          farmer.client.rpc('set_hub_stage', params: {'p_id': o.id, 'p_stage': 'received'}), throwsA(isA<PostgrestException>()),
          reason: 'only staff check in');
      expect((await hub.market.watchOrders(hub.id).first).map((x) => x.id), contains(o.id));
      await hub.client.rpc('set_hub_stage', params: {'p_id': o.id, 'p_stage': 'received'});
      await hub.client.rpc('set_hub_stage', params: {'p_id': o.id, 'p_stage': 'released'});
      expect(await d1.market.claimJob(o.id, d1.id, 'One'), isTrue);
    });

    test('cases: needs two different verified neighbours', () async {
      final c = ReportCase(
          id: 'case-$_run', emoji: '🐄', title: 'Lumpy skin', area: 'Howick', stage: ReportStage.aiChecked, confirmations: 0, aiConfidence: 80, reporterId: farmer.id);
      await farmer.market.putCase(c, farmer.id);
      await farmer.market.confirmCase(c.id, farmer.id);
      await buyer.market.confirmCase(c.id, buyer.id);
      await buyer.market.confirmCase(c.id, buyer.id);
      var got = (await resident.market.watchCases(resident.id).first).firstWhere((x) => x.id == c.id);
      expect(got.confirmations, 1);
      await d1.market.confirmCase(c.id, d1.id);
      got = (await resident.market.watchCases(resident.id).first).firstWhere((x) => x.id == c.id);
      expect(got.stage, ReportStage.corroborated);
    });

    test('water: provider publishes, residents vote once, provider dispatches', () async {
      final zone = WaterZone(
          id: 'z-$_run', name: 'Test zone', provider: 'Utility', reservoir: 'Dam', population: 1000, voteThreshold: 2, readings: [WaterReading(DateTime.now(), 30)]);
      await expectLater(resident.water.upsertZone(zone), throwsA(isA<PostgrestException>()));
      await utility.water.upsertZone(zone);
      final z = (await resident.water.watchZones().first).firstWhere((x) => x.id == zone.id);
      expect(await resident.water.vote(z, resident.id), VoteResult.counted);
      expect(await resident.water.vote(z, resident.id), VoteResult.alreadyVoted);
      expect(await d2.water.vote(z, d2.id), VoteResult.counted);
      var inc = activeIncidentFor(await resident.water.watchIncidents().first, zone.id)!;
      expect(inc.stage, IncidentStage.requested);
      expect(inc.votes, 2);
      expect(await resident.water.hasVoted(inc.id, resident.id), isTrue);
      await utility.water.acknowledge(inc.id);
      await utility.water.dispatch(inc.id, trucks: 2, etaMinutes: 45, note: 'on the way');
      inc = activeIncidentFor(await resident.water.watchIncidents().first, zone.id)!;
      expect(inc.stage, IncidentStage.dispatched);
      await utility.water.resolve(inc.id);
      expect(activeIncidentFor(await resident.water.watchIncidents().first, zone.id), isNull);
      await resident.water.savePrefs(resident.id, const WaterPrefs(household: 4, tankLitres: 5000, herd: 0));
      expect((await resident.water.loadPrefs(resident.id))!.tankLitres, 5000);
      expect(await buyer.water.loadPrefs(resident.id), isNull, reason: 'prefs are private');
    });

    test('roads: warnings are shared and sightings add up', () async {
      final now = DateTime.now();
      final h = RoadHazard(
          id: 'h-$_run', kind: HazardKind.flooding, lat: -29.9, lng: 30.9, reportedAt: now, lastSeen: now, reporter: d1.id, reporterName: 'One', confirms: [d1.id]);
      await d1.roads.save(h);
      final seen = (await d2.roads.watch().first).firstWhere((x) => x.id == h.id);
      expect(seen.confirms, [d1.id]);
      await d2.roads.save(seen.seenBy(d2.id, DateTime.now()));
      final after = (await d1.roads.watch().first).firstWhere((x) => x.id == h.id);
      expect(after.confirms.length, 2);
    });

    test('warehouse: farm announces, staff check in, the farm sees its tag', () async {
      final lot = StockLot(
          id: 'lot-$_run',
          hub: 'Durban hub',
          farmerId: farmer.id,
          farmName: 'Live Farm',
          productName: 'Beef',
          category: Category.meat,
          unit: 'kg',
          qty: 40,
          remaining: 0,
          zone: StorageZone.chilled,
          useBy: DateTime.now().add(const Duration(days: 5)),
          expectedAt: DateTime.now(),
          status: LotStatus.expected);
      await farmer.warehouse.putLot(lot);
      expect((await buyer.warehouse.watchLots().first).where((x) => x.id == lot.id), isEmpty, reason: 'other farms cannot see it');
      // A farm cannot check its own stock in: the database ignores the change.
      await farmer.warehouse.putLot(lot.copyWith(status: LotStatus.stored, remaining: 40, tag: 'T-1'));
      expect((await hub.warehouse.watchLots().first).firstWhere((x) => x.id == lot.id).status, LotStatus.expected);
      await hub.warehouse.putLot(lot.copyWith(status: LotStatus.stored, remaining: 40, qty: 40, tag: 'T-$_run', bay: 'C1'));
      final mine = (await farmer.warehouse.watchLots().first).firstWhere((x) => x.id == lot.id);
      expect(mine.tag, 'T-$_run');
      expect(mine.status, LotStatus.stored);
    });

    test('roles: staff are read from the table and nobody can add themselves', () async {
      await expectLater(farmer.client.from('staff').insert({'uid': farmer.id}), throwsA(isA<PostgrestException>()));
      final row = await hub.client.from('staff').select('uid').eq('uid', hub.id).maybeSingle();
      expect(row, isNotNull);
      expect(await farmer.client.from('staff').select('uid').eq('uid', hub.id), isEmpty);
    });

    test('live stream: a change on one phone reaches another', () async {
      final o = newOrder('UD-LIVE-S-$_run', buyer.id, farmer.id);
      final stream = farmer.market.watchOrders(farmer.id);
      final seen = expectLater(stream, emitsThrough(predicate<List<Order>>((l) => l.any((x) => x.id == o.id))));
      await Future<void>.delayed(const Duration(seconds: 1));
      await buyer.market.putOrder(o, buyer.id);
      await seen.timeout(const Duration(seconds: 15));
    });
  }, skip: skip);
}
