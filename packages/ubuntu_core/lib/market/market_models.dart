import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// The delivery PIN is never stored in the order document. Drivers can read
/// that document, so it holds only this hash; the buyer keeps the PIN itself.
String hashPin(String orderId, String pin) =>
    sha256.convert(utf8.encode('$orderId:$pin')).toString();

double r2(double v) => (v * 100).roundToDouble() / 100;

enum Category { veg, fruit, grain, dairy, water, essentials }

extension CategoryX on Category {
  String get label => switch (this) {
        Category.veg => 'Veg',
        Category.fruit => 'Fruit',
        Category.grain => 'Grain',
        Category.dairy => 'Dairy & eggs',
        Category.water => 'Water',
        Category.essentials => 'Essentials',
      };
  String get emoji => switch (this) {
        Category.veg => '🥬',
        Category.fruit => '🍊',
        Category.grain => '🌽',
        Category.dairy => '🥚',
        Category.water => '💧',
        Category.essentials => '🔦',
      };
}

/// Every Rand that moves through Nolifa Drop is split by these rules. They are
/// shown to the user at checkout and on the receipt, so the numbers live in
/// one place.
/// The delivery PIN can be tried this many times. The last wrong try locks the
/// order and opens a dispute, so the PIN cannot be guessed.
const maxPinAttempts = 3;

class Fees {
  static const buyerRate = 0.03; // service fee paid by the buyer
  static const buyerMin = 2.0;
  static const buyerMax = 15.0;
  static const baseDelivery = 25.0;
  static const driverShare = 0.80; // of the delivery fee, paid on delivery

  static double buyer(double subtotal) =>
      subtotal <= 0 ? 0 : r2((subtotal * buyerRate).clamp(buyerMin, buyerMax));
}

/// What a farm pays to sell on Nolifa Drop: a monthly platform fee that
/// includes support, plus a commission on each completed sale.
enum Plan { starter, grow, coop }

extension PlanX on Plan {
  String get label => switch (this) {
        Plan.starter => 'Starter',
        Plan.grow => 'Grow',
        Plan.coop => 'Co-op',
      };
  int get price => switch (this) {
        Plan.starter => 49,
        Plan.grow => 99,
        Plan.coop => 199,
      };
  double get commission => switch (this) {
        Plan.starter => 0.08,
        Plan.grow => 0.05,
        Plan.coop => 0.03,
      };
  String get blurb => switch (this) {
        Plan.starter => 'Start selling to your neighbours',
        Plan.grow => 'For active smallholders',
        Plan.coop => 'For co-ops and commercial farms',
      };
  List<String> get perks => switch (this) {
        Plan.starter => [
            'Your own store on Nolifa Drop',
            'Support by chat, weekdays',
            'Escrow and payouts through FNB',
            '8% commission per sale',
          ],
        Plan.grow => [
            'Everything in Starter',
            'Priority support, 7 days a week',
            'Unlimited AI diagnoses and health records',
            '7-day outbreak risk forecast',
            '5% commission per sale',
          ],
        Plan.coop => [
            'Everything in Grow, up to 25 farms',
            'Shared herd and crop records',
            'Bulk-order tools and co-op payouts',
            'Dedicated support line',
            '3% commission per sale',
          ],
      };
}

/// Who brings the order to the buyer.
enum DeliveryMode { platform, self }

extension DeliveryModeX on DeliveryMode {
  String get label => switch (this) {
        DeliveryMode.platform => 'Nolifa Delivery',
        DeliveryMode.self => 'Farm delivers',
      };
  String get emoji => this == DeliveryMode.self ? '🚜' : '🛵';
}

class Product {
  final String id;
  final String name;
  final String emoji;
  final Category category;
  final String farm;
  final double km;
  final double price;
  final double? wasPrice;
  final String unit;
  final int groupTarget;
  final int groupJoined;
  final bool mine;
  final bool rescue;
  final String? ownerId; // uid of the farmer who listed it, null for demo farms
  final int? stock; // units left; null means not tracked (demo farms)
  final bool available; // the farmer can pause a listing without deleting it
  final DeliveryMode delivery;
  final double? deliveryFee; // only used when the farm delivers itself

  const Product({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.farm,
    required this.km,
    required this.price,
    required this.unit,
    this.wasPrice,
    this.groupTarget = 0,
    this.groupJoined = 0,
    this.mine = false,
    this.rescue = false,
    this.ownerId,
    this.stock,
    this.available = true,
    this.delivery = DeliveryMode.platform,
    this.deliveryFee,
  });

  bool get soldOut => stock != null && stock! <= 0;
  bool get buyable => available && !soldOut;

  Product copyWith({
    int? groupJoined,
    String? ownerId,
    bool? mine,
    int? stock,
    bool? available,
    double? price,
    double? wasPrice,
    bool clearWasPrice = false,
    bool? rescue,
    String? farm,
    DeliveryMode? delivery,
    double? deliveryFee,
  }) =>
      Product(
        id: id,
        name: name,
        emoji: emoji,
        category: category,
        farm: farm ?? this.farm,
        km: km,
        price: price ?? this.price,
        unit: unit,
        wasPrice: clearWasPrice ? null : (wasPrice ?? this.wasPrice),
        groupTarget: groupTarget,
        groupJoined: groupJoined ?? this.groupJoined,
        mine: mine ?? this.mine,
        rescue: rescue ?? this.rescue,
        ownerId: ownerId ?? this.ownerId,
        stock: stock ?? this.stock,
        available: available ?? this.available,
        delivery: delivery ?? this.delivery,
        deliveryFee: deliveryFee ?? this.deliveryFee,
      );
}

class OrderLine {
  final String name;
  final String emoji;
  final int qty;
  final double price;
  final bool mine;
  final String? ownerId;
  final String? productId;
  const OrderLine(this.name, this.emoji, this.qty, this.price,
      {this.mine = false, this.ownerId, this.productId});
  double get total => qty * price;
}

enum OrderStatus { newOrder, findingDriver, assigned, pickedUp, delivered }

enum PayMethod { fnbPay, ebucks, instantMoney, cash }

extension PayMethodX on PayMethod {
  String get label => switch (this) {
        PayMethod.fnbPay => 'FNB Pay',
        PayMethod.ebucks => 'eBucks',
        PayMethod.instantMoney => 'Instant Money',
        PayMethod.cash => 'Cash on delivery',
      };
  String get note => switch (this) {
        PayMethod.fnbPay => 'Tap to pay from your FNB account',
        PayMethod.ebucks => 'Use your eBucks balance, earn more back',
        PayMethod.instantMoney => 'No bank account needed',
        PayMethod.cash => 'Pay the driver when it arrives',
      };
  IconData get icon => switch (this) {
        PayMethod.fnbPay => Icons.account_balance_rounded,
        PayMethod.ebucks => Icons.stars_rounded,
        PayMethod.instantMoney => Icons.bolt_rounded,
        PayMethod.cash => Icons.payments_rounded,
      };
}

// ------------------------------------------------------------ disputes

enum DisputeReason { notDelivered, damaged, wrongItems, late, driverConduct, pinLocked }

extension DisputeReasonX on DisputeReason {
  String get label => switch (this) {
        DisputeReason.notDelivered => 'Order never arrived',
        DisputeReason.damaged => 'Items damaged or spoiled',
        DisputeReason.wrongItems => 'Wrong or missing items',
        DisputeReason.late => 'Delivery was very late',
        DisputeReason.driverConduct => 'Problem with the driver',
        DisputeReason.pinLocked => 'Delivery PIN entered wrongly 3 times',
      };
  String get emoji => switch (this) {
        DisputeReason.notDelivered => '📭',
        DisputeReason.damaged => '🥀',
        DisputeReason.wrongItems => '📦',
        DisputeReason.late => '⏰',
        DisputeReason.driverConduct => '🚫',
        DisputeReason.pinLocked => '🔒',
      };
  String get remedy => switch (this) {
        DisputeReason.notDelivered => 'Full refund',
        DisputeReason.damaged => '50% of items refunded',
        DisputeReason.wrongItems => '50% of items refunded',
        DisputeReason.late => 'Delivery fee refunded',
        DisputeReason.driverConduct => 'Delivery fee refunded, driver reviewed',
        DisputeReason.pinLocked => 'Money stays frozen while a mediator reviews the delivery',
      };

  /// Opened by the system, never picked by a buyer.
  bool get systemOnly => this == DisputeReason.pinLocked;
}

enum DisputeStage { open, review, resolved }

enum Outcome { fullRefund, partialRefund, deliveryRefund }

class Dispute {
  final DisputeReason reason;
  final String note;
  final DisputeStage stage;
  final Outcome? outcome;
  final List<(String, DateTime)> timeline;

  const Dispute({
    required this.reason,
    required this.note,
    required this.stage,
    required this.timeline,
    this.outcome,
  });

  Dispute copyWith({DisputeStage? stage, Outcome? outcome, String? event}) => Dispute(
        reason: reason,
        note: note,
        stage: stage ?? this.stage,
        outcome: outcome ?? this.outcome,
        timeline: event == null ? timeline : [...timeline, (event, DateTime.now())],
      );
}

class Order {
  final String id;
  final List<OrderLine> lines;
  final double deliveryFee;
  final double serviceFee;
  final double commission; // seller's rate when the order was placed
  final PayMethod method;
  final OrderStatus status;
  final String customer;
  final String pickup;
  final String dropArea;
  final String? pin; // plain PIN, known only on the buyer's device (and demo seeds)
  final String? pinHash;
  final String? driver;
  final bool driverIsMe;
  final bool customerIsMe;
  final bool farmIsMe;
  final bool pickupProof;
  final int pinAttempts; // wrong PINs entered so far
  final bool released;
  final DateTime placed;
  final DateTime? deliveredAt;
  final Dispute? dispute;
  final int rating;
  final String? customerId;
  final String? farmerId;
  final String? driverId;
  final bool seed; // demo-only order, never synced
  final bool selfDelivery; // the farm brings it, no Nolifa driver

  /// How it travels: 'local', 'hub' or 'farm'. For a hub order, [hub] is the
  /// depot the last-mile driver collects from, and [distanceKm] the farm to door road distance.
  final String route;
  final String? hub;
  final double distanceKm;
  final int rev; // bumped on every write so devices can tell which copy is newer

  const Order({
    required this.id,
    required this.lines,
    required this.deliveryFee,
    required this.method,
    required this.status,
    required this.customer,
    required this.pickup,
    required this.dropArea,
    required this.placed,
    this.serviceFee = 0,
    this.commission = 0.08,
    this.pin,
    this.pinHash,
    this.driver,
    this.driverIsMe = false,
    this.customerIsMe = false,
    this.farmIsMe = false,
    this.pickupProof = false,
    this.pinAttempts = 0,
    this.released = false,
    this.deliveredAt,
    this.dispute,
    this.rating = 0,
    this.customerId,
    this.farmerId,
    this.driverId,
    this.seed = false,
    this.selfDelivery = false,
    this.route = 'local',
    this.hub,
    this.distanceKm = 0,
    this.rev = 0,
  });

  /// Checks an entered PIN against the hash, or the plain PIN on demo orders.
  bool pinMatches(String entered) {
    final e = entered.trim();
    if (pinHash != null) return hashPin(id, e) == pinHash;
    return pin != null && pin == e;
  }

  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => r2(subtotal + deliveryFee + serviceFee);
  double get mySalesGross => lines.where((l) => l.mine).fold(0, (s, l) => s + l.total);

  Outcome? get outcome => dispute?.outcome;
  bool get disputed => dispute != null && dispute!.stage != DisputeStage.resolved;
  bool get settledByDispute => dispute?.stage == DisputeStage.resolved;

  double get farmFactor => switch (outcome) {
        Outcome.fullRefund => 0,
        Outcome.partialRefund => 0.5,
        _ => 1,
      };

  double get driverFactor {
    if (outcome == Outcome.fullRefund) return 0;
    if (dispute?.reason == DisputeReason.driverConduct) return 0;
    return 1;
  }

  double get refund => switch (outcome) {
        Outcome.fullRefund => total,
        Outcome.partialRefund => r2(subtotal * 0.5),
        Outcome.deliveryRefund => deliveryFee,
        null => 0,
      };

  /// What the farmer receives for their own lines after commission.
  double get mySalesNet => r2(mySalesGross * farmFactor * (1 - commission));
  double get myCommission => r2(mySalesGross * farmFactor * commission);
  double get mySales => mySalesGross;
  /// A Nolifa driver gets 80% of the delivery fee. When the farm delivers
  /// itself there is no driver, and the farm keeps the whole delivery fee.
  double get driverPay =>
      selfDelivery ? 0 : r2(deliveryFee * Fees.driverShare * driverFactor);
  double get selfDeliveryPay => selfDelivery ? r2(deliveryFee * driverFactor) : 0;
  double get farmGross => r2(subtotal * farmFactor);
  double get farmNet => r2(farmGross * (1 - commission));
  double get platformTake =>
      r2(total - refund - farmNet - driverPay - selfDeliveryPay);

  Order copyWith({
    OrderStatus? status,
    String? driver,
    bool? driverIsMe,
    bool? released,
    bool? pickupProof,
    int? pinAttempts,
    DateTime? deliveredAt,
    Dispute? dispute,
    int? rating,
    double? commission,
    String? driverId,
    int? rev,
    String? pin,
  }) =>
      Order(
        id: id,
        lines: lines,
        deliveryFee: deliveryFee,
        serviceFee: serviceFee,
        commission: commission ?? this.commission,
        method: method,
        status: status ?? this.status,
        customer: customer,
        pickup: pickup,
        dropArea: dropArea,
        pin: pin ?? this.pin,
        pinHash: pinHash,
        placed: placed,
        driver: driver ?? this.driver,
        driverIsMe: driverIsMe ?? this.driverIsMe,
        customerIsMe: customerIsMe,
        farmIsMe: farmIsMe,
        pickupProof: pickupProof ?? this.pickupProof,
        pinAttempts: pinAttempts ?? this.pinAttempts,
        released: released ?? this.released,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        dispute: dispute ?? this.dispute,
        rating: rating ?? this.rating,
        customerId: customerId,
        farmerId: farmerId,
        driverId: driverId ?? this.driverId,
        seed: seed,
        selfDelivery: selfDelivery,
        route: route,
        hub: hub,
        distanceKm: distanceKm,
        rev: rev ?? this.rev,
      );

  /// Where the driver collects: the hub for a hub order, otherwise the farm.
  String get driverPickup => hub ?? pickup;
}

// ------------------------------------------------------------- alerts

enum AlertKind { water, outbreak, weather, energy, road }

class MarketAlert {
  final String id;
  final String emoji;
  final AlertKind kind;
  final String title;
  final String body;
  final String area;
  final int severity; // 0 info, 1 warning, 2 critical
  final String cta;
  final List<String> bundle; // product ids pre-loaded into the cart
  final bool farmSide;
  final String? trust; // how the alert was verified, shown as a badge

  const MarketAlert({
    required this.id,
    required this.emoji,
    required this.kind,
    required this.title,
    required this.body,
    required this.area,
    required this.severity,
    required this.cta,
    this.bundle = const [],
    this.farmSide = false,
    this.trust,
  });

  Color get color => switch (severity) {
        2 => const Color(0xFFFF6B6B),
        1 => const Color(0xFFE8A33D),
        _ => const Color(0xFF52D1A4),
      };
}

// ----------------------------------------------------- outbreak reports

enum ReportStage { submitted, aiChecked, corroborated, vetVerified, rejected }

extension ReportStageX on ReportStage {
  String get label => switch (this) {
        ReportStage.submitted => 'Submitted',
        ReportStage.aiChecked => 'AI checked',
        ReportStage.corroborated => 'Farms confirmed',
        ReportStage.vetVerified => 'Vet verified',
        ReportStage.rejected => 'Rejected',
      };
  bool get broadcasts =>
      this == ReportStage.corroborated || this == ReportStage.vetVerified;
}

class ReportCase {
  final String id;
  final String emoji;
  final String title;
  final String area;
  final ReportStage stage;
  final int confirmations;
  final int aiConfidence;
  final bool mine;
  final String? reporterId;
  final List<String> confirmedBy;

  const ReportCase({
    required this.id,
    required this.emoji,
    required this.title,
    required this.area,
    required this.stage,
    required this.confirmations,
    required this.aiConfidence,
    this.mine = false,
    this.reporterId,
    this.confirmedBy = const [],
  });

  ReportCase copyWith({ReportStage? stage, int? confirmations, List<String>? confirmedBy}) => ReportCase(
        id: id,
        emoji: emoji,
        title: title,
        area: area,
        stage: stage ?? this.stage,
        confirmations: confirmations ?? this.confirmations,
        aiConfidence: aiConfidence,
        mine: mine,
        reporterId: reporterId,
        confirmedBy: confirmedBy ?? this.confirmedBy,
      );
}

// -------------------------------------------------------------- ledger

enum LedgerKind { held, payout, fee, refund, driver }

class LedgerEntry {
  final String title;
  final String sub;
  final double amount; // signed: negative leaves you, positive reaches you
  final LedgerKind kind;
  final DateTime time;
  LedgerEntry(this.title, this.sub, this.amount, this.kind, [DateTime? time])
      : time = time ?? DateTime.now();
}

// ----------------------------------------------------------------- KYC

enum KycRole { driver, farmer }

class KycStep {
  final String id;
  final String title;
  final String detail;
  final IconData icon;
  const KycStep(this.id, this.title, this.detail, this.icon);
}

const driverSteps = <KycStep>[
  KycStep('id', 'Verify your ID with FNB', 'South African ID checked against Home Affairs', Icons.badge_rounded),
  KycStep('selfie', 'Selfie match', 'Live selfie matched to your ID photo', Icons.face_retouching_natural_rounded),
  KycStep('payout', 'Payout account', 'FNB account or Instant Money number', Icons.account_balance_wallet_rounded),
  KycStep('vehicle', 'Vehicle and safety', 'Bike, car or bakkie plus safety briefing', Icons.two_wheeler_rounded),
];

const farmerSteps = <KycStep>[
  KycStep('id', 'Verify your ID with FNB', 'South African ID checked against Home Affairs', Icons.badge_rounded),
  KycStep('location', 'Pin your farm', 'GPS location confirmed on site', Icons.pin_drop_rounded),
  KycStep('payout', 'Payout account', 'FNB account or Instant Money number', Icons.account_balance_wallet_rounded),
];


// ------------------------------------------------- SUPPLY RISK RADAR (B2B)

enum Risk { clear, watch, high }

extension RiskX on Risk {
  String get label => switch (this) {
        Risk.clear => 'Clear',
        Risk.watch => 'Watch',
        Risk.high => 'High risk',
      };
  Color get color => switch (this) {
        Risk.clear => const Color(0xFF52D1A4),
        Risk.watch => const Color(0xFFE8A33D),
        Risk.high => const Color(0xFFFF6B6B),
      };
}

/// A farm that supplies a business, with a 7-day disease-risk forecast.
/// Suppliers only appear here after they joined the buyer's network and agreed
/// to share their status with that buyer.
class Supplier {
  final String id;
  final String name;
  final String emoji;
  final String product;
  final String district;
  final List<int> forecast; // 7 days, 0 to 100
  const Supplier(this.id, this.name, this.emoji, this.product, this.district, this.forecast);
}

class Alternative {
  final String id;
  final String name;
  final String product;
  final String district;
  final int km;
  final int capacity; // % of the volume they can absorb
  final String premium;
  const Alternative(this.id, this.name, this.product, this.district, this.km, this.capacity, this.premium);
}

enum BizPlan { watch, command, enterprise }

extension BizPlanX on BizPlan {
  String get label => switch (this) {
        BizPlan.watch => 'Watch',
        BizPlan.command => 'Command',
        BizPlan.enterprise => 'Enterprise',
      };
  String get price => switch (this) {
        BizPlan.watch => 'R1 500 / month',
        BizPlan.command => 'R6 500 / month',
        BizPlan.enterprise => 'Custom',
      };
  List<String> get perks => switch (this) {
        BizPlan.watch => [
            'Up to 10 suppliers',
            'Weekly risk digest by email',
            'Verified cases only, district level',
          ],
        BizPlan.command => [
            'Up to 50 suppliers',
            'Live alerts the moment a case is verified',
            '7-day forecast per supplier',
            'Backup supplier matching and quotes',
          ],
        BizPlan.enterprise => [
            'Unlimited suppliers and API access',
            'Audit trail for food-safety compliance',
            'Dedicated analyst and custom forecasts',
          ],
      };
}

const suppliers = <Supplier>[
  Supplier('s-1', 'Mkhize Beef', '🐄', 'Beef', 'Pinetown', [38, 52, 64, 72, 80, 85, 90]),
  Supplier('s-2', 'Khumalo Poultry', '🐔', 'Poultry', 'Verulam', [30, 34, 40, 44, 48, 50, 52]),
  Supplier('s-3', 'Dlamini Mill', '🌽', 'Maize', 'Eshowe', [25, 28, 35, 40, 44, 48, 52]),
  Supplier('s-4', 'Naidoo Orchards', '🍊', 'Citrus', 'Ixopo', [10, 12, 15, 14, 18, 20, 22]),
  Supplier('s-5', 'Zulu Co-op', '🫘', 'Beans', 'Estcourt', [8, 9, 12, 11, 13, 15, 14]),
  Supplier('s-6', 'Sithole Growers', '🍅', 'Tomatoes', 'Hillcrest', [20, 26, 30, 36, 38, 40, 41]),
];

const alternatives = <Alternative>[
  Alternative('a-1', 'Estcourt Cattle Co-op', 'Beef', 'Estcourt', 142, 40, '+4% per kg'),
  Alternative('a-2', 'Ixopo Beef Collective', 'Beef', 'Ixopo', 96, 25, '+2% per kg'),
  Alternative('a-3', 'Eshowe Layer Farms', 'Poultry', 'Eshowe', 118, 35, '+3% per tray'),
  Alternative('a-4', 'Greytown Maize Growers', 'Maize', 'Greytown', 131, 50, 'same price'),
  Alternative('a-5', 'Midlands Veg Hub', 'Tomatoes', 'Howick', 88, 30, '+2% per kg'),
];


// ------------------------------------------------------------ profile

/// What a person tells the app about themselves. Private to them, and shared
/// across Nolifa Drop, Nolifa Grow and Nolifa Delivery when the backend is on.
class ProfileSettings {
  final String name;
  final String phone;

  /// The number that passed the one-time-code check. Changing the phone number
  /// makes this stop matching, so verification belongs to a number, not a person's word.
  final String verifiedPhone;
  final String address; // street and number
  final String suburb;
  final bool notifyOrders;
  final bool notifyWater;
  final bool notifyOutbreaks;

  // Farm store details (used by Nolifa Grow).
  final String farmName;
  final String farmAbout;
  final DeliveryMode delivery;
  final double deliveryFee;

  const ProfileSettings({
    this.name = '',
    this.phone = '',
    this.verifiedPhone = '',
    this.address = '',
    this.suburb = '',
    this.notifyOrders = true,
    this.notifyWater = true,
    this.notifyOutbreaks = true,
    this.farmName = '',
    this.farmAbout = '',
    this.delivery = DeliveryMode.platform,
    this.deliveryFee = 0,
  });

  ProfileSettings copyWith({
    String? name,
    String? phone,
    String? verifiedPhone,
    String? address,
    String? suburb,
    bool? notifyOrders,
    bool? notifyWater,
    bool? notifyOutbreaks,
    String? farmName,
    String? farmAbout,
    DeliveryMode? delivery,
    double? deliveryFee,
  }) =>
      ProfileSettings(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        verifiedPhone: verifiedPhone ?? this.verifiedPhone,
        address: address ?? this.address,
        suburb: suburb ?? this.suburb,
        notifyOrders: notifyOrders ?? this.notifyOrders,
        notifyWater: notifyWater ?? this.notifyWater,
        notifyOutbreaks: notifyOutbreaks ?? this.notifyOutbreaks,
        farmName: farmName ?? this.farmName,
        farmAbout: farmAbout ?? this.farmAbout,
        delivery: delivery ?? this.delivery,
        deliveryFee: deliveryFee ?? this.deliveryFee,
      );

  bool get phoneVerified => phone.trim().isNotEmpty && verifiedPhone == phone.trim();

  /// "12 Jabu Rd, Umlazi", or whatever part is filled in.
  String get addressLine => [address, suburb].where((p) => p.trim().isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'verifiedPhone': verifiedPhone,
        'address': address,
        'suburb': suburb,
        'notifyOrders': notifyOrders,
        'notifyWater': notifyWater,
        'notifyOutbreaks': notifyOutbreaks,
        'farmName': farmName,
        'farmAbout': farmAbout,
        'delivery': delivery.name,
        'deliveryFee': deliveryFee,
      };

  factory ProfileSettings.fromJson(Map<String, dynamic> m) => ProfileSettings(
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        verifiedPhone: m['verifiedPhone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        suburb: m['suburb'] as String? ?? '',
        notifyOrders: m['notifyOrders'] as bool? ?? true,
        notifyWater: m['notifyWater'] as bool? ?? true,
        notifyOutbreaks: m['notifyOutbreaks'] as bool? ?? true,
        farmName: m['farmName'] as String? ?? '',
        farmAbout: m['farmAbout'] as String? ?? '',
        delivery: DeliveryMode.values.firstWhere((d) => d.name == m['delivery'],
            orElse: () => DeliveryMode.platform),
        deliveryFee: (m['deliveryFee'] as num?)?.toDouble() ?? 0,
      );
}

/// A farm's registration to sell on Nolifa Drop. Selling needs all three:
/// registered, verified (see [farmerSteps]) and a paid monthly plan.
/// How a farm gets its land and crops checked. Rural farms are far from a
/// surveyor, so there are three routes and none of them is mandatory first.
enum InspectionRoute { surveyor, extensionOfficer, coopDay }

extension InspectionRouteX on InspectionRoute {
  String get label => switch (this) {
        InspectionRoute.surveyor => 'Surveyor visit',
        InspectionRoute.extensionOfficer => 'Extension officer',
        InspectionRoute.coopDay => 'Co-op inspection day',
      };
  String get blurb => switch (this) {
        InspectionRoute.surveyor => 'A Nolifa surveyor comes to your farm. Best near towns.',
        InspectionRoute.extensionOfficer =>
          'Your local agricultural extension officer checks on a routine visit. Free in most districts.',
        InspectionRoute.coopDay =>
          'A surveyor visits your co-op or village on one day and checks several farms together.',
      };
  int get waitDays => switch (this) {
        InspectionRoute.surveyor => 14,
        InspectionRoute.extensionOfficer => 7,
        InspectionRoute.coopDay => 21,
      };
}

enum InspectionStatus { none, requested, scheduled, passed, failed }

/// Rules for selling before the on-site inspection is done. Fresh whole
/// produce is low risk, so a farm that shows its land and crops by geo-tagged
/// photos can start selling straight away with limits. Eggs, milk and anything
/// processed wait for the inspection. The limits lift when it passes.
class Inspection {
  static const provisionalDays = 45;
  static const provisionalCap = 2000.0; // Rand of sales
  static const highRisk = {Category.dairy, Category.essentials};
}

class BusinessProfile {
  final bool registered;
  final String kind; // 'individual' | 'cooperative' | 'company'
  final String regNumber; // company or co-op registration, optional
  final bool planPaid;

  /// Geo-tagged photos of the land, the crop and the water source were added.
  final bool evidenceDone;
  final int? provisionalSince; // epoch ms; selling with limits starts here
  final InspectionStatus inspection;
  final InspectionRoute route;
  final int? visitOn; // epoch ms of the booked or expected visit

  const BusinessProfile({
    this.registered = false,
    this.kind = 'individual',
    this.regNumber = '',
    this.planPaid = false,
    this.evidenceDone = false,
    this.provisionalSince,
    this.inspection = InspectionStatus.none,
    this.route = InspectionRoute.extensionOfficer,
    this.visitOn,
  });

  BusinessProfile copyWith({
    bool? registered,
    String? kind,
    String? regNumber,
    bool? planPaid,
    bool? evidenceDone,
    int? provisionalSince,
    InspectionStatus? inspection,
    InspectionRoute? route,
    int? visitOn,
  }) =>
      BusinessProfile(
        registered: registered ?? this.registered,
        kind: kind ?? this.kind,
        regNumber: regNumber ?? this.regNumber,
        planPaid: planPaid ?? this.planPaid,
        evidenceDone: evidenceDone ?? this.evidenceDone,
        provisionalSince: provisionalSince ?? this.provisionalSince,
        inspection: inspection ?? this.inspection,
        route: route ?? this.route,
        visitOn: visitOn ?? this.visitOn,
      );

  Map<String, dynamic> toJson() => {
        'registered': registered,
        'kind': kind,
        'regNumber': regNumber,
        'planPaid': planPaid,
        'evidenceDone': evidenceDone,
        'provisionalSince': provisionalSince,
        'inspection': inspection.name,
        'route': route.name,
        'visitOn': visitOn,
      };

  factory BusinessProfile.fromJson(Map<String, dynamic> m) => BusinessProfile(
        registered: m['registered'] as bool? ?? false,
        kind: m['kind'] as String? ?? 'individual',
        regNumber: m['regNumber'] as String? ?? '',
        planPaid: m['planPaid'] as bool? ?? false,
        evidenceDone: m['evidenceDone'] as bool? ?? false,
        provisionalSince: (m['provisionalSince'] as num?)?.toInt(),
        inspection: InspectionStatus.values.firstWhere((e) => e.name == m['inspection'],
            orElse: () => InspectionStatus.none),
        route: InspectionRoute.values.firstWhere((e) => e.name == m['route'],
            orElse: () => InspectionRoute.extensionOfficer),
        visitOn: (m['visitOn'] as num?)?.toInt(),
      );
}
