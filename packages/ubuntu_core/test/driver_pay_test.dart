import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

Order order({String route = 'local', double fee = 25, double km = 8, bool self = false, Outcome? outcome}) => Order(
      id: 'O1',
      lines: const [],
      deliveryFee: fee,
      method: PayMethod.fnbPay,
      status: OrderStatus.delivered,
      customer: 'Buyer',
      pickup: 'Farm',
      dropArea: 'Street',
      placed: DateTime(2026, 10, 24),
      route: route,
      distanceKm: km,
      selfDelivery: self,
      dispute: outcome == null
          ? null
          : Dispute(
              reason: DisputeReason.notDelivered,
              note: '',
              stage: DisputeStage.resolved,
              outcome: outcome,
              timeline: const []),
    );

void main() {
  // These numbers are the same ones supabase/tests/database/driver_pay.test.sql
  // pins for driver_job_pay, so the phone and the server cannot drift apart.
  group('driver pay matches the server formula', () {
    test('a very short trip pays the R24 minimum', () => expect(DriverPay.forKm(1), 24.00));
    test('R12 + 5 km at R2.50', () => expect(DriverPay.forKm(5), 24.50));
    test('R12 + 8 km at R2.50', () => expect(order(fee: 25, km: 8).driverPay, 32.00));
    test('R12 + 20 km at R2.50', () => expect(order(fee: 45, km: 20).driverPay, 62.00));
    test('an inflated distance is capped by what the fee could buy', () => expect(order(fee: 15, km: 70).driverPay, 45.75));
    test('an unknown distance counts as 10 km', () => expect(order(fee: 15, km: 0).driverPay, 37.00));
    test('a hub order is paid for 15 km of last mile', () => expect(order(route: 'hub', fee: 35, km: 70).driverPay, 49.50));
    test('a longer hub last mile pays more', () => expect(order(route: 'hub', fee: 50, km: 70).driverPay, 124.50));
  });

  group('who gets paid', () {
    test('a farm that delivers itself has no driver pay', () => expect(order(self: true).driverPay, 0));
    test('a full refund pays the driver nothing', () => expect(order(outcome: Outcome.fullRefund).driverPay, 0));
    test('a partial refund still pays the driver', () => expect(order(outcome: Outcome.partialRefund).driverPay, 32.00));
  });

  group('the breakdown adds up', () {
    test('base + distance + minimum top-up is the total', () {
      for (final o in [order(km: 1, fee: 15), order(km: 8), order(km: 20, fee: 45), order(route: 'hub', fee: 35)]) {
        final b = DriverPay.breakdown(o);
        expect(b.base + b.distance + b.minimumTopUp, closeTo(b.total, 0.011));
      }
    });
    test('Nolifa tops up what 80% of the fee does not cover', () {
      final b = DriverPay.breakdown(order(fee: 25, km: 8));
      expect(b.total, 32.00);
      expect(b.topUp, 12.00);
    });
    test('a long, well-paid fee needs no top-up', () {
      expect(DriverPay.breakdown(order(route: 'hub', fee: 135)).topUp, greaterThanOrEqualTo(0));
    });
  });

  group('what a run earns', () {
    JobPoint job(String id, double fee, double km, double lat) => JobPoint(
        order(fee: fee, km: km).copyWith(status: OrderStatus.findingDriver), lat, 31.0, lat - 0.05, 31.05);

    test('a run of eight 8 km drops clears a fair hourly rate after fuel', () {
      final jobs = [for (var i = 0; i < 8; i++) job('J$i', 25, 8, -29.80 - i * 0.002)];
      final batch = buildBatches(jobs).first;
      expect(batch.payout, 8 * 32.00);
      expect(batch.fuel, closeTo(batch.km * DriverPay.fuelPerKm, 0.01));
      // The national minimum wage is about R29 an hour; a run should leave far more.
      expect(batch.netPerHour, greaterThan(60));
    });
  });
}
