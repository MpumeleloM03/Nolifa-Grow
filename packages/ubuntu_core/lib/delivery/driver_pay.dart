import '../market/market_models.dart' show Order, r2;

/// What a driver is paid, worked out from the work and not from the buyer's fee.
///
/// R12 for each delivery (collect, hand over, check the PIN) plus R2.50 for
/// every road kilometre, never under R24. The server holds the same formula
/// (`driver_job_pay`) and writes the amount when the PIN is accepted, so the
/// number a driver sees here is the number they are owed. Both are pinned to
/// the same test values.
///
/// Fuel and wear are not paid on top: R2.50 a km is meant to cover R1.90 of
/// fuel and the rest of the vehicle, which is why the driver screens show pay
/// per hour both before and after fuel.
class DriverPay {
  static const base = 12.0;
  static const perKm = 2.5;
  static const minimum = 24.0;

  /// A small car at 8.5 L/100 km and about R22 a litre, rounded up.
  static const fuelPerKm = 1.9;

  /// What the buyer's fee pays towards it. Nolifa adds the rest.
  static const feeShare = 0.8;

  /// A hub order is paid for the last mile only. The buyer's R35 hub fee
  /// buys the first 30 km; each km beyond that adds R1.
  static double hubKm(double fee) => fee > 35 ? 30 + (fee - 35) : 15;

  /// The road distance this order is paid for. A local trip is capped by what
  /// the fee could have bought, so inflating the distance gains nothing.
  static double km(Order o) => kmFor(route: o.route, fee: o.deliveryFee, distanceKm: o.distanceKm);

  static double kmFor({required String route, required double fee, required double distanceKm}) {
    if (route == 'hub') return hubKm(fee);
    final claimed = distanceKm <= 0 ? 10.0 : distanceKm;
    final cap = 6 + ((fee * 2 - 15) / 2).clamp(0.0, double.infinity);
    return (claimed < cap ? claimed : cap).clamp(1.0, 80.0);
  }

  /// Pay for one delivery, before any dispute adjustment.
  static double forKm(double km) => r2((base + perKm * km) < minimum ? minimum : (base + perKm * km));

  static PayBreakdown breakdown(Order o) {
    final k = km(o);
    final distance = r2(perKm * k);
    final total = forKm(k);
    final fromFee = r2(o.deliveryFee * feeShare);
    return PayBreakdown(
      km: r2(k),
      base: base,
      distance: distance,
      minimumTopUp: r2((total - base - distance).clamp(0.0, double.infinity)),
      total: total,
      topUp: r2((total - fromFee).clamp(0.0, double.infinity)),
    );
  }

  static double fuelCost(double km) => r2(km * fuelPerKm);
}

class PayBreakdown {
  final double km;
  final double base;
  final double distance;
  final double minimumTopUp;
  final double total;

  /// What Nolifa adds above 80% of the buyer's delivery fee.
  final double topUp;
  const PayBreakdown({
    required this.km,
    required this.base,
    required this.distance,
    required this.minimumTopUp,
    required this.total,
    required this.topUp,
  });
}
