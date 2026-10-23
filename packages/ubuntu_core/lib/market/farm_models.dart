import 'market_models.dart';

/// Demo details for the seeded farms: what a real farm earns over time
/// (ratings, speed) is unknown on day one, so only demo farms carry them.
class FarmMeta {
  final double rating;
  final int reviews;
  final int etaMinutes;
  final String tagline;
  final String emoji;
  const FarmMeta(this.rating, this.reviews, this.etaMinutes, this.tagline, this.emoji);
}

const demoFarmMeta = <String, FarmMeta>{
  'Mkhize Family Farm': FarmMeta(4.8, 212, 35, 'Leafy greens, picked this morning', '🥬'),
  'Sithole Growers': FarmMeta(4.6, 148, 40, 'Tomatoes, onions and peppers', '🍅'),
  'Dlamini Mill': FarmMeta(4.7, 96, 55, 'Stone-ground maize meal and samp', '🌽'),
  'Khumalo Poultry': FarmMeta(4.9, 301, 30, 'Free-range eggs and chickens', '🥚'),
  'Naidoo Orchards': FarmMeta(4.5, 87, 60, 'Citrus and avocados from Ixopo', '🍊'),
  'Zulu Co-op': FarmMeta(4.6, 64, 45, 'Beans, butternut and more', '🫘'),
  'Nolifa Depot': FarmMeta(4.8, 530, 25, 'Water, gas and power for outages', '💧'),
};

/// A farm as a shopper sees it: a name, how far, how it delivers, and what it
/// sells. Built from the products on offer, so a farm appears the moment its
/// first product does.
class Farm {
  final String name;
  final String? ownerId;
  final List<Product> products;
  final double km;
  final DeliveryMode delivery;
  final double deliveryFee;
  final bool mine;

  const Farm({
    required this.name,
    required this.ownerId,
    required this.products,
    required this.km,
    required this.delivery,
    required this.deliveryFee,
    required this.mine,
  });

  String get id => ownerId ?? name;
  FarmMeta? get meta => demoFarmMeta[name];
  double? get rating => meta?.rating;
  int get reviews => meta?.reviews ?? 0;
  int get etaMinutes => meta?.etaMinutes ?? 45;
  String get tagline => meta?.tagline ?? 'Fresh from the farm';
  String get emoji => meta?.emoji ?? products.first.emoji;
  bool get verified => meta != null || ownerId != null;
  bool get hasRescue => products.any((p) => p.rescue);

  /// "Farm delivers, free" or "Nolifa Delivery, R25".
  String get deliveryLabel {
    if (delivery == DeliveryMode.self) {
      return deliveryFee <= 0
          ? 'Farm delivers · free'
          : 'Farm delivers · R${deliveryFee.toStringAsFixed(0)}';
    }
    return 'Nolifa Delivery · R${Fees.baseDelivery.toStringAsFixed(0)}';
  }
}

/// Groups what is on offer into farms, nearest first. [query] matches a farm
/// name or any of its products; [category] keeps farms that sell something in it.
List<Farm> groupFarms(
  Iterable<Product> products, {
  String query = '',
  Category? category,
}) {
  final byFarm = <String, List<Product>>{};
  for (final p in products.where((p) => p.available)) {
    byFarm.putIfAbsent(p.ownerId ?? p.farm, () => []).add(p);
  }
  final q = query.trim().toLowerCase();
  final farms = <Farm>[];
  for (final list in byFarm.values) {
    final first = list.first;
    final farm = Farm(
      name: first.farm,
      ownerId: first.ownerId,
      products: list,
      km: list.map((p) => p.km).reduce((a, b) => a < b ? a : b),
      delivery: first.delivery,
      deliveryFee: first.deliveryFee ?? 0,
      mine: list.any((p) => p.mine),
    );
    if (category != null && !list.any((p) => p.category == category)) continue;
    if (q.isNotEmpty &&
        !farm.name.toLowerCase().contains(q) &&
        !list.any((p) => p.name.toLowerCase().contains(q))) {
      continue;
    }
    farms.add(farm);
  }
  farms.sort((a, b) => a.km.compareTo(b.km));
  return farms;
}
