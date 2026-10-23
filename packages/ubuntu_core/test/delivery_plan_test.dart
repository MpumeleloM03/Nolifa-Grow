import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

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
  }
  MarketStore get store => c.read(marketProvider.notifier);
  MarketState get s => c.read(marketProvider);
  void dispose() => c.dispose();
}

const umlazi = (-29.9697, 30.8860);
const durbanFarm = (-29.8700, 30.9000); // a farm about 14 km from Umlazi
const pmbFarm = (-29.6200, 30.4000); // Mkhize Family Farm

void main() {
  group('choosing the route', () {
    test('a farm close to the buyer delivers locally, same day', () {
      final p = planDelivery(farm: durbanFarm, buyer: umlazi);
      expect(p.route, DeliveryRoute.local);
      expect(p.farmKm, inInclusiveRange(8, 25));
      expect(p.eta, 'Today');
      expect(p.hub, isNull);
      expect(p.driverPickup('Dlamini Mill'), 'Dlamini Mill');
      expect(p.fee, p.directFee);
    });

    test('a far farm goes through the hub nearest the buyer, and costs far less than a direct run', () {
      final p = planDelivery(farm: pmbFarm, buyer: umlazi);
      expect(p.route, DeliveryRoute.hub);
      expect(p.farmKm, greaterThan(70));
      expect(p.hub!.id, 'dbn');
      expect(p.driverPickup('Mkhize Family Farm'), 'Durban hub');
      expect(p.eta, '1 to 2 days');
      expect(p.lastMileKm, lessThan(25));
      expect(p.fee, 35);
      expect(p.directFee, greaterThan(150));
      expect(p.saving, greaterThan(110));
    });

    test('a buyer near Pietermaritzburg is served from the Pietermaritzburg hub, even for a coastal farm', () {
      final p = planDelivery(farm: (-29.7100, 30.9600), buyer: (-29.5800, 30.3900));
      expect(p.route, DeliveryRoute.hub);
      expect(p.hub!.id, 'pmb');
    });

    test('the last mile adds R1 a km past 30 km from the hub', () {
      // A buyer about 60 km from the Pietermaritzburg hub.
      final p = planDelivery(farm: (-29.7100, 30.9600), buyer: (-29.2000, 30.0800));
      expect(p.route, DeliveryRoute.hub);
      expect(p.lastMileKm, greaterThan(30));
      expect(p.fee, closeTo(35 + (p.lastMileKm - 30), 0.01));
    });

    test('a farm that delivers itself keeps its own fee', () {
      final p = planDelivery(farm: pmbFarm, buyer: umlazi, farmDelivers: true, farmFee: 15);
      expect(p.route, DeliveryRoute.farm);
      expect(p.fee, 15);
    });

    test('a group buy halves the fee on either route', () {
      final local = planDelivery(farm: durbanFarm, buyer: umlazi);
      final half = planDelivery(farm: durbanFarm, buyer: umlazi, groupFactor: 0.5);
      expect(half.fee, closeTo(local.fee / 2, 0.01));
      final hub = planDelivery(farm: pmbFarm, buyer: umlazi, groupFactor: 0.5);
      expect(hub.fee, 17.5);
    });

    test('with an unknown address it quotes the standard R25 and says it is an estimate', () {
      final p = planDelivery(farm: pmbFarm, buyer: null);
      expect(p.fee, 25);
      expect(p.estimated, isTrue);
      expect(p.summary, contains('Add your address'));
    });

    test('direct delivery price grows with distance but starts at R15', () {
      expect(directFeeFor(1), 15);
      expect(directFeeFor(5), 15);
      expect(directFeeFor(13), 31);
      expect(directFeeFor(1000), 400);
    });
  });

  group('in the shop', () {
    Phone phone() => Phone('u', LocalMarketRepository.memory());

    test('the order remembers how it travels, and the driver collects at the hub', () {
      final p = phone();
      p.store.updateProfile(p.s.profile.copyWith(address: '12 Main Road', suburb: 'Umlazi'));
      p.store.startNewBasket('p-tomato'); // Sithole Growers, North Coast
      final plan = p.s.deliveryPlan!;
      final id = p.store.place(PayMethod.cash);
      final o = p.s.orderById(id)!;
      expect(o.route, plan.route.name);
      expect(o.deliveryFee, plan.fee);
      expect(o.distanceKm, closeTo(plan.farmKm, 0.1));
      if (plan.route == DeliveryRoute.hub) {
        expect(o.hub, plan.hub!.name);
        expect(o.driverPickup, plan.hub!.name);
      } else {
        expect(o.driverPickup, o.pickup);
      }
      p.dispose();
    });

    test('the route, hub and distance survive saving and reloading an order', () {
      final o = Order(
        id: 'o1',
        lines: const [OrderLine('Spinach', '🥬', 1, 20)],
        deliveryFee: 35,
        method: PayMethod.cash,
        status: OrderStatus.findingDriver,
        customer: 'T',
        pickup: 'Mkhize Family Farm',
        dropArea: 'Umlazi',
        placed: DateTime(2026, 10, 23),
        route: 'hub',
        hub: 'Durban hub',
        distanceKm: 88.4,
      );
      final back = orderFromJson(orderToJson(o, 'u'), 'u');
      expect(back.route, 'hub');
      expect(back.hub, 'Durban hub');
      expect(back.distanceKm, 88.4);
      expect(back.driverPickup, 'Durban hub');
    });
  });
}
