import '../roads/road_models.dart' show metresBetween;
import '../market/market_models.dart' show r2;

/// How an order travels, chosen from the distance between the farm and the
/// buyer, the way a big online shop does it.
///
///  - [local]: one driver collects from the farm and brings it to the door.
///    Used when the farm is close.
///  - [hub]: the farm drops the order at the nearest Nolifa hub (or a driver
///    collects several farms' orders on one run), and a last-mile driver brings
///    it from the hub nearest the buyer. Used when the farm is far, so nobody
///    drives 70 km out and 90 km back for one bag of spinach.
///  - [farm]: the farm delivers itself, at its own fee.
enum DeliveryRoute {
  local('Local delivery'),
  hub('Hub delivery'),
  farm('Farm delivers');

  final String label;
  const DeliveryRoute(this.label);

  static DeliveryRoute parse(String? raw) =>
      DeliveryRoute.values.firstWhere((r) => r.name == raw, orElse: () => DeliveryRoute.local);
}

/// A Nolifa hub: a depot where farm orders are dropped and sorted, and from
/// where last-mile drivers deliver. These are planned sites, not yet open.
class Hub {
  final String id;
  final String name;
  final double lat;
  final double lng;
  const Hub(this.id, this.name, this.lat, this.lng);
}

const hubs = <Hub>[
  Hub('dbn', 'Durban hub', -29.8650, 31.0100),
  Hub('pmb', 'Pietermaritzburg hub', -29.6010, 30.3794),
  Hub('rb', 'Richards Bay hub', -28.7830, 32.0380),
];

/// Straight-line distance becomes road distance with this factor, which is
/// what a typical South African road network adds. When the app has a real
/// routed distance it uses that instead.
const roadFactor = 1.3;

/// Farms within this road distance of the buyer deliver locally.
const localMaxKm = 25.0;

class DeliveryPlan {
  final DeliveryRoute route;
  final double fee;

  /// What a single driver going farm to door would charge for the same trip.
  final double directFee;
  final double farmKm; // farm to buyer, by road
  final Hub? hub; // the hub the last mile starts from
  final double lastMileKm; // distance the last driver travels
  final String eta;
  final String summary;
  final bool estimated; // true when a place could not be located

  const DeliveryPlan({
    required this.route,
    required this.fee,
    required this.directFee,
    required this.farmKm,
    required this.hub,
    required this.lastMileKm,
    required this.eta,
    required this.summary,
    this.estimated = false,
  });

  /// What the buyer saves against one driver going the whole way.
  double get saving => r2((directFee - fee).clamp(0, double.infinity));

  /// The place the driver collects from.
  String driverPickup(String farm) => hub?.name ?? farm;
}

/// A direct trip charges R15 for the first 5 km, then R2 for every km after.
double directFeeFor(double km) => r2((15 + 2 * (km - 5).clamp(0.0, double.infinity)).clamp(15.0, 400.0));

Hub nearestHub(double lat, double lng) {
  Hub best = hubs.first;
  var bd = double.infinity;
  for (final h in hubs) {
    final d = metresBetween(lat, lng, h.lat, h.lng);
    if (d < bd) {
      bd = d;
      best = h;
    }
  }
  return best;
}

double _roadKm(double lat1, double lng1, double lat2, double lng2) =>
    metresBetween(lat1, lng1, lat2, lng2) / 1000 * roadFactor;

/// Chooses how an order should travel and what it costs.
///
/// [farm] and [buyer] are (lat, lng), either may be null when a place is not
/// known; then [fallbackKm] (the distance the shop shows) is used and the plan
/// is marked as an estimate. [groupDiscount] is the group-buy discount, 0.5 for
/// half price.
DeliveryPlan planDelivery({
  required (double, double)? farm,
  required (double, double)? buyer,
  double fallbackKm = 10,
  bool farmDelivers = false,
  double farmFee = 0,
  double groupFactor = 1,
}) {
  final known = farm != null && buyer != null;
  final km = known ? _roadKm(farm.$1, farm.$2, buyer.$1, buyer.$2) : fallbackKm;
  final direct = directFeeFor(km);

  if (farmDelivers) {
    return DeliveryPlan(
      route: DeliveryRoute.farm,
      fee: r2(farmFee),
      directFee: direct,
      farmKm: km,
      hub: null,
      lastMileKm: km,
      eta: 'Set by the farm',
      summary: 'The farm brings it itself.',
      estimated: !known,
    );
  }

  // Without both places we cannot tell near from far, so quote the standard
  // R25 and say it is an estimate until the buyer adds an address.
  if (!known) {
    return DeliveryPlan(
      route: DeliveryRoute.local,
      fee: r2(25 * groupFactor),
      directFee: 25,
      farmKm: km,
      hub: null,
      lastMileKm: km,
      eta: 'Today',
      summary: 'Add your address to see the exact delivery and price.',
      estimated: true,
    );
  }

  if (km <= localMaxKm) {
    final fee = r2(direct * groupFactor);
    return DeliveryPlan(
      route: DeliveryRoute.local,
      fee: fee,
      directFee: direct,
      farmKm: km,
      hub: null,
      lastMileKm: km,
      eta: 'Today',
      summary: 'A driver collects from the farm and brings it to your door. ${km.round()} km.',
      estimated: !known,
    );
  }

  // Far away: through the hub nearest the buyer.
  final h = known ? nearestHub(buyer.$1, buyer.$2) : hubs.first;
  final last = known ? _roadKm(h.lat, h.lng, buyer.$1, buyer.$2) : 15.0;
  // R25 flat for the hub to door run within 30 km of the hub, then R1 a km. The
  // farm leg is a drop-off or a shared collection run, paid for by the R10 hub
  // handling charge.
  final fee = r2((25 + 10 + (last - 30).clamp(0, double.infinity) * 1.0) * groupFactor);
  return DeliveryPlan(
    route: DeliveryRoute.hub,
    fee: fee,
    directFee: direct,
    farmKm: km,
    hub: h,
    lastMileKm: last,
    eta: '1 to 2 days',
    summary: 'The farm is ${km.round()} km away, so it goes through the ${h.name} and a local driver brings it the last '
        '${last.round()} km.',
    estimated: !known,
  );
}
