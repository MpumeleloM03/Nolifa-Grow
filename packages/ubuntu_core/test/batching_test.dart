import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'shared_fakes.dart';

Order _o(String id, String farm, String drop, {int qty = 20, double fee = 40}) => Order(
      id: id,
      lines: [OrderLine('Beef', '🥩', qty, 100)],
      deliveryFee: fee,
      method: PayMethod.fnbPay,
      status: OrderStatus.findingDriver,
      customer: 'Buyer',
      pickup: farm,
      dropArea: drop,
      placed: DateTime(2026, 10, 24),
      customerId: 'b-$id',
      farmerId: 'f-$farm',
    );

JobPoint _j(Order o, double pLat, double pLng, double dLat, double dLng) => JobPoint(o, pLat, pLng, dLat, dLng);

void main() {
  // Three farms around Howick, deliveries in Pietermaritzburg. One far away in Richards Bay.
  final howickA = (-29.47, 30.23);
  final howickB = (-29.49, 30.25);
  final howickC = (-29.45, 30.20);
  final pmb = (-29.60, 30.38);
  final pmb2 = (-29.62, 30.40);
  final rb = (-28.78, 32.04);

  List<JobPoint> sample() => [
        _j(_o('1', 'Farm A', 'Scottsville'), howickA.$1, howickA.$2, pmb.$1, pmb.$2),
        _j(_o('2', 'Farm A', 'Hayfields'), howickA.$1, howickA.$2, pmb2.$1, pmb2.$2),
        _j(_o('3', 'Farm B', 'Northdale'), howickB.$1, howickB.$2, pmb.$1 + 0.01, pmb.$2),
        _j(_o('4', 'Farm C', 'Napierville'), howickC.$1, howickC.$2, pmb2.$1, pmb2.$2 + 0.01),
        _j(_o('5', 'Far Farm', 'Empangeni'), rb.$1, rb.$2, rb.$1 + 0.02, rb.$2),
      ];

  group('batches', () {
    test('close farms and close drops become one batch; the far job stays alone', () {
      final b = buildBatches(sample());
      expect(b.length, 2);
      final big = b.firstWhere((x) => x.jobs.length == 4);
      expect(big.farms, 3);
      expect(big.drops, 4);
      expect(big.items, 80);
      expect(b.firstWhere((x) => x.jobs.length == 1).jobs.single.order.id, '5');
    });

    test('every job is in exactly one batch', () {
      final ids = [for (final b in buildBatches(sample())) ...b.orderIds]..sort();
      expect(ids, ['1', '2', '3', '4', '5']);
    });

    test('the payout is what the jobs pay, added up', () {
      final b = buildBatches(sample()).firstWhere((x) => x.jobs.length == 4);
      expect(b.payout, 4 * _o('x', 'a', 'b').driverPay);
      expect(b.payout, greaterThan(_o('x', 'a', 'b').driverPay * 3));
    });

    test('all collections come before any delivery, and orders from one farm share a stop', () {
      final b = buildBatches(sample()).firstWhere((x) => x.jobs.length == 4);
      final kinds = [for (final s in b.stops) s.kind];
      final lastPickup = kinds.lastIndexOf(StopKind.pickup);
      final firstDrop = kinds.indexOf(StopKind.drop);
      expect(lastPickup < firstDrop, isTrue);
      final farmA = b.stops.firstWhere((s) => s.label == 'Farm A');
      expect(farmA.orders.length, 2);
      expect(farmA.items, 40);
    });

    test('the nearest farm to the driver is collected first', () {
      final b = buildBatches(sample(), startLat: howickC.$1, startLng: howickC.$2).firstWhere((x) => x.jobs.length == 4);
      expect(b.stops.first.label, 'Farm C');
    });

    test('limits: no more than the farm and drop caps', () {
      final many = [for (var i = 0; i < 20; i++) _j(_o('j$i', 'Farm ${i % 6}', 'Street $i'), howickA.$1, howickA.$2, pmb.$1, pmb.$2)];
      for (final b in buildBatches(many, maxFarms: 3, maxDrops: 5)) {
        expect(b.farms <= 3, isTrue);
        expect(b.drops <= 5, isTrue);
      }
      expect([for (final b in buildBatches(many, maxFarms: 3, maxDrops: 5)) ...b.orderIds].length, 20);
    });

    test('richest batch first, and no jobs means no batches', () {
      final b = buildBatches(sample());
      expect(b.first.payout >= b.last.payout, isTrue);
      expect(buildBatches(const []), isEmpty);
    });

    test('kmBetween is about right: Durban to Pietermaritzburg is roughly 80 km', () {
      final km = kmBetween(-29.8587, 31.0218, -29.6006, 30.3794);
      expect(km, inInclusiveRange(60, 75));
    });
  });

  group('taking a batch', () {
    Future<(SharedMarketDb, FakeSharedMarketRepository)> seeded() async {
      final db = SharedMarketDb();
      final repo = FakeSharedMarketRepository(db);
      for (final id in ['1', '2', '3']) {
        await repo.putOrder(_o(id, 'Farm A', 'Street'), 'buyer');
      }
      return (db, repo);
    }

    test('one driver gets all of them', () async {
      final (db, repo) = await seeded();
      expect(await repo.claimBatch(['1', '2', '3'], 'd1', 'One'), isTrue);
      expect(db.orders.values.every((o) => o['driverId'] == 'd1' && o['status'] == 'assigned'), isTrue);
    });

    test('a second driver gets none once any job is gone', () async {
      final (db, repo) = await seeded();
      await repo.claimJob('2', 'd1', 'One');
      expect(await repo.claimBatch(['1', '2', '3'], 'd2', 'Two'), isFalse);
      expect(db.orders['1']!['driverId'], isNull, reason: 'all or nothing');
      expect(db.orders['3']!['driverId'], isNull);
    });

    test('a job that does not exist fails the batch', () async {
      final (_, repo) = await seeded();
      expect(await repo.claimBatch(['1', 'nope'], 'd1', 'One'), isFalse);
    });
  });
}
