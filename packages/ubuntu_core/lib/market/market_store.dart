import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase/resilient.dart' show friendlyError;
import '../delivery/delivery_plan.dart';
import 'fatboy_range.dart';
import 'market_codec.dart';
import 'places.dart';
import 'farm_models.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// How long a buyer has to confirm or dispute after delivery. Production uses
/// two hours; the demo compresses it so a judge can watch the whole loop.
Duration protectionWindow = const Duration(seconds: 12);

const _products = <Product>[
  ...fatboyRange,
  // Mkhize Family Farm delivers itself.
  Product(
      id: 'p-spinach',
      name: 'Spinach bunch',
      emoji: '🥬',
      category: Category.veg,
      farm: 'Mkhize Family Farm',
      km: 6.4,
      price: 12,
      unit: 'bunch',
      groupTarget: 12,
      groupJoined: 9,
      delivery: DeliveryMode.self,
      deliveryFee: 15),
  Product(
      id: 'p-cabbage',
      name: 'Cabbage head',
      emoji: '🥗',
      category: Category.veg,
      farm: 'Mkhize Family Farm',
      km: 6.4,
      price: 22,
      unit: 'head',
      delivery: DeliveryMode.self,
      deliveryFee: 15),
  Product(
      id: 'p-carrot',
      name: 'Carrots 1kg',
      emoji: '🥕',
      category: Category.veg,
      farm: 'Mkhize Family Farm',
      km: 6.4,
      price: 18,
      unit: 'bag',
      delivery: DeliveryMode.self,
      deliveryFee: 15),
  Product(
      id: 'p-tomato',
      name: 'Tomatoes 2kg',
      emoji: '🍅',
      category: Category.veg,
      farm: 'Sithole Growers',
      km: 9.8,
      price: 38,
      wasPrice: 52,
      unit: 'bag',
      rescue: true),
  Product(
      id: 'p-onion',
      name: 'Onions 2kg',
      emoji: '🧅',
      category: Category.veg,
      farm: 'Sithole Growers',
      km: 9.8,
      price: 30,
      unit: 'bag'),
  Product(
      id: 'p-pepper',
      name: 'Mixed peppers 500g',
      emoji: '🫑',
      category: Category.veg,
      farm: 'Sithole Growers',
      km: 9.8,
      price: 26,
      unit: 'punnet'),
  Product(
      id: 'p-mielie',
      name: 'Maize meal 10kg',
      emoji: '🌽',
      category: Category.grain,
      farm: 'Dlamini Mill',
      km: 12.3,
      price: 119,
      unit: 'bag',
      groupTarget: 8,
      groupJoined: 3),
  Product(
      id: 'p-samp',
      name: 'Samp 2kg',
      emoji: '🌾',
      category: Category.grain,
      farm: 'Dlamini Mill',
      km: 12.3,
      price: 64,
      unit: 'bag'),
  // Khumalo Poultry delivers itself, free.
  Product(
      id: 'p-eggs',
      name: 'Free-range eggs x30',
      emoji: '🥚',
      category: Category.dairy,
      farm: 'Khumalo Poultry',
      km: 4.2,
      price: 84,
      unit: 'tray',
      delivery: DeliveryMode.self,
      deliveryFee: 0),
  Product(
      id: 'p-chicken',
      name: 'Free-range chicken',
      emoji: '🍗',
      category: Category.dairy,
      farm: 'Khumalo Poultry',
      km: 4.2,
      price: 96,
      unit: 'whole',
      delivery: DeliveryMode.self,
      deliveryFee: 0),
  Product(
      id: 'p-orange',
      name: 'Oranges 3kg',
      emoji: '🍊',
      category: Category.fruit,
      farm: 'Naidoo Orchards',
      km: 15.0,
      price: 49,
      wasPrice: 65,
      unit: 'bag',
      rescue: true),
  Product(
      id: 'p-lemon',
      name: 'Lemons 1kg',
      emoji: '🍋',
      category: Category.fruit,
      farm: 'Naidoo Orchards',
      km: 15.0,
      price: 35,
      unit: 'bag'),
  Product(
      id: 'p-avo',
      name: 'Avocados x4',
      emoji: '🥑',
      category: Category.fruit,
      farm: 'Naidoo Orchards',
      km: 15.0,
      price: 59,
      unit: 'pack'),
  Product(
      id: 'p-beans',
      name: 'Dry sugar beans 2kg',
      emoji: '🫘',
      category: Category.grain,
      farm: 'Zulu Co-op',
      km: 7.7,
      price: 56,
      unit: 'bag'),
  Product(
      id: 'p-butternut',
      name: 'Butternut',
      emoji: '🎃',
      category: Category.veg,
      farm: 'Zulu Co-op',
      km: 7.7,
      price: 28,
      unit: 'each'),
  // Everything for an outage, from one store, so a power or water kit is one order.
  Product(
      id: 'p-water',
      name: 'Drinking water 25L',
      emoji: '💧',
      category: Category.water,
      farm: 'Nolifa Depot',
      km: 2.1,
      price: 45,
      unit: 'bottle',
      groupTarget: 10,
      groupJoined: 7),
  Product(
      id: 'p-candle',
      name: 'Candles + matches pack',
      emoji: '🕯️',
      category: Category.essentials,
      farm: 'Nolifa Depot',
      km: 2.1,
      price: 29,
      unit: 'pack'),
  Product(
      id: 'p-bank',
      name: 'Power bank 10,000mAh',
      emoji: '🔋',
      category: Category.essentials,
      farm: 'Nolifa Depot',
      km: 2.1,
      price: 249,
      unit: 'each'),
  Product(
      id: 'p-gas',
      name: 'Gas refill 9kg',
      emoji: '🔥',
      category: Category.essentials,
      farm: 'Nolifa Depot',
      km: 2.1,
      price: 289,
      unit: 'refill'),
];

const _alerts = <MarketAlert>[
  MarketAlert(
    id: 'a-power',
    emoji: '⚡',
    kind: AlertKind.energy,
    title: 'Load shedding stage 4 tonight',
    body: 'Two 4-hour blocks. Charge devices and plan cooking before 18:00.',
    area: 'Durban',
    severity: 1,
    cta: 'Get a power kit',
    bundle: ['p-candle', 'p-bank', 'p-gas'],
    trust: 'Utility schedule',
  ),
  MarketAlert(
    id: 'a-flood',
    emoji: '🌧️',
    kind: AlertKind.road,
    title: 'Flood warning on the N2 and R102',
    body: 'Deliveries re-routed through the M7. Expect +15 min.',
    area: 'eThekwini',
    severity: 1,
    cta: 'See safe delivery slots',
    trust: 'Weather service',
  ),
  MarketAlert(
    id: 'a-armyworm',
    emoji: '🐛',
    kind: AlertKind.outbreak,
    title: 'Fall armyworm spotted 12 km away',
    body: '3 farms reported damage on maize this week. Scout your fields today.',
    area: 'Inanda',
    severity: 2,
    cta: 'Scan a leaf now',
    farmSide: true,
    trust: 'Vet verified',
  ),
  MarketAlert(
    id: 'a-fmd',
    emoji: '🐄',
    kind: AlertKind.outbreak,
    title: 'Foot-and-mouth movement restriction',
    body: 'No cattle movement in this district. Check your herd register.',
    area: 'Pietermaritzburg',
    severity: 2,
    cta: 'Check herd',
    farmSide: true,
    trust: 'State vet notice',
  ),
  MarketAlert(
    id: 'a-frost',
    emoji: '❄️',
    kind: AlertKind.weather,
    title: 'Frost risk tonight',
    body: 'Cover seedlings. Harvest ripe tomatoes today or list them at a rescue price.',
    area: 'Midlands',
    severity: 1,
    cta: 'List produce',
    farmSide: true,
    trust: 'Weather service',
  ),
];

const _cases = <ReportCase>[
  ReportCase(
      id: 'c-1',
      emoji: '🐛',
      title: 'Fall armyworm on maize',
      area: 'Inanda',
      stage: ReportStage.vetVerified,
      confirmations: 3,
      aiConfidence: 94),
  ReportCase(
      id: 'c-2',
      emoji: '🐔',
      title: 'Suspected Newcastle disease',
      area: 'Verulam',
      stage: ReportStage.corroborated,
      confirmations: 2,
      aiConfidence: 81),
  ReportCase(
      id: 'c-4',
      emoji: '🐄',
      title: 'Foot-and-mouth suspected in cattle',
      area: 'Pinetown',
      stage: ReportStage.vetVerified,
      confirmations: 3,
      aiConfidence: 91),
  ReportCase(
      id: 'c-3',
      emoji: '🍂',
      title: 'Leaf rust on beans',
      area: 'Hillcrest',
      stage: ReportStage.aiChecked,
      confirmations: 1,
      aiConfidence: 72),
];

enum PinOutcome { delivered, wrong, locked, error }

class PinResult {
  final PinOutcome outcome;
  final int attemptsLeft;
  const PinResult(this.outcome, this.attemptsLeft);
  bool get delivered => outcome == PinOutcome.delivered;
  bool get locked => outcome == PinOutcome.locked;
}

const Object _keep = Object();

class MarketState {
  final List<Product> products;
  final List<MarketAlert> alerts;
  final Map<String, int> cart;
  final List<Order> orders;
  final bool driverOnline;
  final double farmEarned;
  final double driverEarned;
  final double saved;
  final Set<String> joined;
  final Plan plan;
  final List<LedgerEntry> ledger;
  final List<ReportCase> cases;
  final Set<String> driverKyc;
  final Set<String> farmKyc;
  final bool creditConsent;
  final BizPlan bizPlan;
  final Set<String> rerouted;
  final Set<String> quotes;
  final bool demoMode;
  final Set<String> paid;
  final Map<String, String> pins;
  final Set<String> stockApplied;
  final ProfileSettings profile;
  final BusinessProfile business;

  /// What Nolifa's staff decided on this farm's application: true approved,
  /// false not approved (yet), null when the app is not using applications
  /// (the phone-only mode and the tests). Never saved: it comes from the server.
  final bool? serverApproved;

  /// Same for the driver application: true approved, false not yet, null when
  /// the app does not use driver applications.
  final bool? serverDriverApproved;

  const MarketState({
    required this.products,
    required this.alerts,
    required this.cart,
    required this.orders,
    required this.driverOnline,
    required this.farmEarned,
    required this.driverEarned,
    required this.saved,
    required this.joined,
    required this.plan,
    required this.ledger,
    required this.cases,
    required this.driverKyc,
    required this.farmKyc,
    required this.creditConsent,
    required this.bizPlan,
    required this.rerouted,
    required this.quotes,
    required this.demoMode,
    required this.paid,
    required this.pins,
    this.stockApplied = const {},
    this.profile = const ProfileSettings(),
    this.business = const BusinessProfile(),
    this.serverApproved,
    this.serverDriverApproved,
  });

  MarketState copyWith({
    List<Product>? products,
    Map<String, int>? cart,
    List<Order>? orders,
    bool? driverOnline,
    double? farmEarned,
    double? driverEarned,
    double? saved,
    Set<String>? joined,
    Plan? plan,
    List<LedgerEntry>? ledger,
    List<ReportCase>? cases,
    List<MarketAlert>? alerts,
    Set<String>? driverKyc,
    Set<String>? farmKyc,
    bool? creditConsent,
    BizPlan? bizPlan,
    Set<String>? rerouted,
    Set<String>? quotes,
    bool? demoMode,
    Set<String>? paid,
    Map<String, String>? pins,
    Set<String>? stockApplied,
    ProfileSettings? profile,
    BusinessProfile? business,
    Object? serverApproved = _keep,
    Object? serverDriverApproved = _keep,
  }) =>
      MarketState(
        products: products ?? this.products,
        alerts: alerts ?? this.alerts,
        cart: cart ?? this.cart,
        orders: orders ?? this.orders,
        driverOnline: driverOnline ?? this.driverOnline,
        farmEarned: farmEarned ?? this.farmEarned,
        driverEarned: driverEarned ?? this.driverEarned,
        saved: saved ?? this.saved,
        joined: joined ?? this.joined,
        plan: plan ?? this.plan,
        ledger: ledger ?? this.ledger,
        cases: cases ?? this.cases,
        driverKyc: driverKyc ?? this.driverKyc,
        farmKyc: farmKyc ?? this.farmKyc,
        creditConsent: creditConsent ?? this.creditConsent,
        bizPlan: bizPlan ?? this.bizPlan,
        rerouted: rerouted ?? this.rerouted,
        quotes: quotes ?? this.quotes,
        demoMode: demoMode ?? this.demoMode,
        paid: paid ?? this.paid,
        pins: pins ?? this.pins,
        stockApplied: stockApplied ?? this.stockApplied,
        profile: profile ?? this.profile,
        business: business ?? this.business,
        serverApproved: identical(serverApproved, _keep) ? this.serverApproved : serverApproved as bool?,
        serverDriverApproved: identical(serverDriverApproved, _keep) ? this.serverDriverApproved : serverDriverApproved as bool?,
      );

  /// Risk for one supplier: the worst of the near-term forecast and any
  /// *verified* outbreak case in their district. Unverified reports never move
  /// a supplier's rating, so one bad report cannot damage a farm.
  (Risk, String) riskOf(Supplier s) {
    final verified = cases
        .where((c) => c.area == s.district && c.stage.broadcasts)
        .toList();
    final peak = s.forecast.take(3).reduce((a, b) => a > b ? a : b);
    if (verified.any((c) => c.stage == ReportStage.vetVerified)) {
      return (Risk.high, '${verified.first.title}, vet verified in ${s.district}');
    }
    if (verified.isNotEmpty) {
      return (Risk.watch, '${verified.first.title}, confirmed by nearby farms');
    }
    if (peak >= 70) return (Risk.high, 'Forecast risk ${peak}% within 3 days');
    if (peak >= 40) return (Risk.watch, 'Forecast risk rising to ${peak}%');
    return (Risk.clear, 'No verified cases or forecast risk');
  }

  int get highRiskCount =>
      suppliers.where((s) => riskOf(s).$1 == Risk.high && !rerouted.contains(s.id)).length;

  int get cartCount => cart.values.fold(0, (a, b) => a + b);

  double get cartSubtotal => cart.entries.fold(0.0, (s, e) {
        final p = products.firstWhere((p) => p.id == e.key);
        return s + p.price * e.value;
      });

  /// The farm the basket is from. A basket holds one farm at a time, like one
  /// restaurant at a time on a food app, because one person brings it.
  Product? get cartFirst => cart.isEmpty ? null : products.firstWhere((p) => p.id == cart.keys.first);
  String? get cartFarm => cartFirst?.farm;
  bool get cartSelfDelivery => cartFirst?.delivery == DeliveryMode.self;

  /// How this basket would travel and what it costs: local when the farm is
  /// near the buyer's address, through a hub when it is far, or by the farm
  /// itself. Null for an empty basket.
  DeliveryPlan? get deliveryPlan {
    final first = cartFirst;
    if (first == null) return null;
    final from = lookupPlace(first.place ?? '') ?? lookupPlace(first.farm);
    // The demo buyer lives in Umlazi until they add an address, so the hub and
    // local routes can be shown.
    final to = lookupPlace(profile.addressLine.isEmpty ? (demoMode ? 'Umlazi' : '') : profile.addressLine);
    final groupFactor = cart.keys.any((id) => joined.contains(id)) ? 0.5 : 1.0;
    return planDelivery(
      farm: from,
      buyer: to,
      fallbackKm: first.km > 0 ? first.km : 10,
      farmDelivers: first.delivery == DeliveryMode.self,
      farmFee: first.deliveryFee ?? 0,
      groupFactor: groupFactor,
    );
  }

  double get deliveryFee => deliveryPlan?.fee ?? 0;

  List<Farm> get farms => groupFarms(products);

  /// Selling on Nolifa Drop needs all three: registered, verified, plan paid.
  /// A person the network can trust to count: a verified farm, or someone whose
  /// phone number passed the one-time-code check. One verified number, one voice.
  bool get isVerifiedMember => farmVerified || profile.phoneVerified;

  /// Only verified farmers can confirm someone else's outbreak report.
  bool get canConfirmOutbreaks => farmVerified;

  bool get inspectionPassed => business.inspection == InspectionStatus.passed;

  /// Selling with limits, before the on-site inspection: needs the land and
  /// crop photos, and lasts [Inspection.provisionalDays].
  bool get provisionalActive {
    final since = business.provisionalSince;
    if (inspectionPassed || !business.evidenceDone || since == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(since)).inDays <
        Inspection.provisionalDays;
  }

  int get provisionalDaysLeft {
    final since = business.provisionalSince;
    if (since == null) return 0;
    final left = Inspection.provisionalDays -
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(since)).inDays;
    return left < 0 ? 0 : left;
  }

  bool get canSell =>
      serverApproved != false &&
      business.registered &&
      farmVerified &&
      business.planPaid &&
      (inspectionPassed || provisionalActive) &&
      business.inspection != InspectionStatus.failed;

  /// Sales still allowed while provisional. Unlimited once inspected.
  double get provisionalRoom => inspectionPassed
      ? double.infinity
      : (Inspection.provisionalCap - farmEarned).clamp(0, Inspection.provisionalCap).toDouble();

  /// Why a category cannot be listed yet, or null when it can.
  String? listBlock(Category c) {
    if (!canSell) return 'Finish the steps on the Business page first.';
    if (inspectionPassed) return null;
    if (Inspection.highRisk.contains(c)) {
      return '${c.label} needs the on-site inspection first. Fresh produce you can list now.';
    }
    if (provisionalRoom <= 0) {
      return 'You reached the limit for farms not yet inspected. Book your inspection to lift it.';
    }
    return null;
  }

  double get serviceFee => Fees.buyer(cartSubtotal);
  double get cartTotal => r2(cartSubtotal + deliveryFee + serviceFee);

  /// Seller commission that applies to this cart: the user's own plan rate when
  /// the cart holds their produce, the standard rate otherwise.
  double get cartCommission =>
      cart.keys.any((id) => products.firstWhere((p) => p.id == id).mine)
          ? plan.commission
          : Plan.starter.commission;

  Order? orderById(String id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  List<Order> get myOrders => orders.where((o) => o.customerIsMe).toList();
  List<Order> get farmOrders => orders.where((o) => o.farmIsMe).toList();
  /// Jobs a driver can take. A hub order only opens once hub staff release it.
  List<Order> get openJobs => orders
      .where((o) =>
          o.status == OrderStatus.findingDriver &&
          o.driver == null &&
          (o.hubStage == null || o.hubStage == 'released'))
      .toList();

  /// Hub orders still passing through the hub, newest first.
  List<Order> get hubOrders => orders.where((o) => o.atHubWork).toList();
  List<Order> get myJobs =>
      orders.where((o) => o.driverIsMe && o.status != OrderStatus.delivered).toList();

  /// Money the buyer has paid that is still protected in escrow.
  double get escrowHeld => orders
      .where((o) =>
          o.customerIsMe &&
          !o.released &&
          o.method != PayMethod.cash)
      .fold(0.0, (s, o) => s + o.total);

  bool get driverVerified => serverDriverApproved ?? (driverKyc.length == driverSteps.length);
  bool get farmVerified => serverApproved ?? (farmKyc.length == farmerSteps.length);

  /// How ready this household is for a disruption, 0 to 100.
  int get resilience {
    final ids = <String>{
      ...cart.keys,
      for (final o in myOrders) ...o.lines.map((l) => l.name),
    };
    bool has(Category c) => products.any((p) =>
        p.category == c && (ids.contains(p.id) || ids.contains(p.name)));
    var score = 38;
    if (has(Category.water)) score += 24;
    if (has(Category.essentials)) score += 20;
    if (has(Category.grain) || has(Category.veg)) score += 12;
    if (myOrders.any((o) => o.released)) score += 6;
    return score.clamp(0, 100);
  }

  /// A simple credit-readiness read built from sales and deliveries.
  int get creditScore => (520 + (farmEarned / 8) + (driverEarned / 12)).round().clamp(300, 850);
}

/// Who the signed-in user is. Each app overrides these three providers with its
/// own sign-in and storage; the defaults keep the module usable on its own.
/// The shipped apps set this to true so demo content is never shown.
final marketStartsLiveProvider = Provider<bool>((ref) => false);

final marketUidProvider = Provider<String>((ref) => 'guest');

/// The decision on this farm's application, from the database. Null in apps and
/// tests that do not use applications. Nolifa Grow supplies the real one.
final sellerApprovalProvider = Provider<bool?>((ref) => null);

/// Whether Nolifa has approved this person as a driver. Null where driver
/// applications are not used.
final driverApprovalProvider = Provider<bool?>((ref) => null);

/// The plan staff have set for this farm. Null where plans are not server managed.
/// The commission the server charges comes from this, never from the phone.
final sellerPlanProvider = Provider<Plan?>((ref) => null);

/// Why the last order could not be placed, shown once by the checkout screen.
final placeErrorProvider = StateProvider<String?>((ref) => null);


final marketNameProvider = Provider<String>((ref) => 'Neighbour');

/// On-device storage by default. An app swaps in the Firestore repository once
/// Firebase is connected.
final marketRepositoryProvider =
    Provider<MarketRepository>((ref) => LocalMarketRepository());

const _simDriverName = 'Sipho M.';
const _seedCaseIds = {'c-1', 'c-2', 'c-3', 'c-4'};

class MarketStore extends Notifier<MarketState> {
  final _timers = <Timer>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _simmed = <String>{};
  final _hubSimmed = <String>{};
  final _releasing = <String>{};
  final _disputing = <String>{};
  final _caseSim = <String, ReportCase>{}; // demo progress the server never sees
  final _rng = Random.secure();
  late String _uid;
  late String _name;
  late MarketRepository _repo;
  bool _ready = false;
  bool _disposed = false;
  int _case = 4;

  bool get shared => _repo.shared;

  /// The name orders and receipts carry: the one the person saved in their
  /// profile, else the one from sign-in.
  String get _display {
    final n = state.profile.name.trim();
    return n.isEmpty ? _name : n.split(' ').first;
  }

  /// A farm's public name: what they typed, else "<first name>'s Farm".
  String get _farmName {
    final f = state.profile.farmName.trim();
    return f.isEmpty ? "$_display's Farm" : f;
  }

  @override
  MarketState build() {
    _uid = ref.watch(marketUidProvider);
    _name = ref.watch(marketNameProvider);
    _repo = ref.watch(marketRepositoryProvider);
    _ready = false;
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      for (final t in _timers) {
        t.cancel();
      }
      for (final s in _subs) {
        s.cancel();
      }
    });
    // Everything private (balances, plan, checks, cart) is saved on change.
    listenSelf((_, next) {
      if (_ready && !_disposed) _guard(_repo.savePrivate(_uid, _privateOf(next)));
    });
    _startsLive = ref.read(marketStartsLiveProvider);
    ref.listen<bool?>(sellerApprovalProvider, (_, a) => _applyApproval(a));
    ref.listen<bool?>(driverApprovalProvider, (_, a) {
      if (!_disposed) state = state.copyWith(serverDriverApproved: a);
    });
    ref.listen<Plan?>(sellerPlanProvider, (_, p) {
      if (!_disposed && p != null) state = state.copyWith(plan: p, business: state.business.copyWith(planPaid: true));
    });
    Future.microtask(() {
      if (_disposed) return;
      _applyApproval(ref.read(sellerApprovalProvider));
      final d = ref.read(driverApprovalProvider);
      if (d != null) state = state.copyWith(serverDriverApproved: d);
      final p = ref.read(sellerPlanProvider);
      if (p != null) state = state.copyWith(plan: p, business: state.business.copyWith(planPaid: true));
    });
    Future.microtask(_attach);
    return _startsLive ? _stripDemo(_demoState()) : _demoState();
  }

  /// Staff approval of the farm application opens the selling steps that the
  /// application itself covers: business registered, identity checked, land shown.
  void _applyApproval(bool? approved) {
    if (_disposed) return;
    if (approved != true) {
      state = state.copyWith(serverApproved: approved);
      return;
    }
    final b = state.business;
    state = state.copyWith(
      serverApproved: true,
      business: b.copyWith(
        registered: true,
        evidenceDone: true,
        provisionalSince: b.provisionalSince ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// True in the shipped apps: they never show demo content and the demo switch
  /// is hidden.
  bool _startsLive = false;

  /// The same state with every piece of demo content taken out: only real
  /// people, real listings and real time are left.
  MarketState _stripDemo(MarketState s) => s.copyWith(
        demoMode: false,
        products: s.products.where((p) => p.ownerId != null).toList(),
        orders: s.orders.where((o) => !o.seed).toList(),
        cases: s.cases.where((c) => !_seedCaseIds.contains(c.id)).toList(),
        alerts: const [],
        cart: const {},
        ledger: const [],
        farmEarned: 0,
        driverEarned: 0,
        saved: 0,
        joined: const {},
        driverKyc: const {},
        farmKyc: const {},
        driverOnline: false,
        rerouted: const {},
        quotes: const {},
      );

  // ------------------------------------------------------ state setup

  MarketState _demoState() {
    final now = DateTime.now();
    return MarketState(
      products: _products,
      alerts: _alerts,
      cases: _cases,
      cart: const {},
      driverOnline: false,
      farmEarned: 1240,
      driverEarned: 310,
      saved: 86,
      joined: const {},
      plan: Plan.starter,
      creditConsent: true,
      bizPlan: BizPlan.command,
      rerouted: const {},
      quotes: const {},
      demoMode: true,
      paid: const {},
      pins: const {},
      driverKyc: const {'id'},
      farmKyc: const {'id', 'payout'},
      ledger: [
        LedgerEntry('Sale payout', 'UD-1018 · 6 × Spinach bunch, less 8% commission', 66.24,
            LedgerKind.payout, now.subtract(const Duration(days: 1, hours: 2))),
        LedgerEntry('Sale payout', 'UD-1012 · 2 × Free-range eggs, less 8% commission', 154.56,
            LedgerKind.payout, now.subtract(const Duration(days: 2, hours: 5))),
        LedgerEntry('Delivery payout', 'UD-1009 · Umlazi to Chatsworth', 20.0,
            LedgerKind.driver, now.subtract(const Duration(days: 3))),
      ],
      orders: _seedOrders(now),
    );
  }

  List<Order> _seedOrders(DateTime now) => [
        Order(
          id: 'UD-1031',
          lines: const [
            OrderLine('Spinach bunch', '🥬', 6, 12, mine: true),
            OrderLine('Free-range eggs x30', '🥚', 1, 84, mine: true),
          ],
          deliveryFee: 25,
          serviceFee: 4.68,
          method: PayMethod.instantMoney,
          status: OrderStatus.newOrder,
          customer: 'Thandi N.',
          pickup: 'Your farm',
          dropArea: 'Umlazi V Section',
          pin: '4821',
          placed: now.subtract(const Duration(minutes: 6)),
          farmIsMe: true,
          seed: true,
        ),
        Order(
          id: 'UD-1032',
          lines: const [OrderLine('Tomatoes 2kg', '🍅', 3, 38, mine: true)],
          deliveryFee: 25,
          serviceFee: 3.42,
          method: PayMethod.fnbPay,
          status: OrderStatus.newOrder,
          customer: 'Mama Joy Spaza',
          pickup: 'Your farm',
          dropArea: 'Kwa-Mashu',
          pin: '7305',
          placed: now.subtract(const Duration(minutes: 2)),
          farmIsMe: true,
          seed: true,
        ),
        Order(
          id: 'UD-1033',
          lines: const [OrderLine('Maize meal 10kg', '🌽', 2, 119)],
          deliveryFee: 30,
          serviceFee: 7.14,
          method: PayMethod.ebucks,
          status: OrderStatus.findingDriver,
          customer: 'Sizwe K.',
          pickup: 'Dlamini Mill',
          dropArea: 'Chatsworth',
          pin: '1946',
          placed: now.subtract(const Duration(minutes: 4)),
          seed: true,
        ),
        Order(
          id: 'UD-1034',
          lines: const [OrderLine('Drinking water 25L', '💧', 4, 45)],
          deliveryFee: 20,
          serviceFee: 5.4,
          method: PayMethod.cash,
          status: OrderStatus.findingDriver,
          customer: 'Aunty Rose',
          pickup: 'Nolifa Depot',
          dropArea: 'Umlazi D Section',
          pin: '5582',
          placed: now.subtract(const Duration(minutes: 1)),
          seed: true,
        ),
      ];

  PrivateState _privateOf(MarketState s) => PrivateState(
        demoMode: s.demoMode,
        plan: s.plan,
        bizPlan: s.bizPlan,
        creditConsent: s.creditConsent,
        driverOnline: s.driverOnline,
        farmEarned: s.farmEarned,
        driverEarned: s.driverEarned,
        saved: s.saved,
        joined: s.joined,
        driverKyc: s.driverKyc,
        farmKyc: s.farmKyc,
        rerouted: s.rerouted,
        quotes: s.quotes,
        paid: s.paid,
        pins: s.pins,
        stockApplied: s.stockApplied,
        profile: s.profile,
        business: s.business,
        cart: s.cart,
        ledger: s.ledger,
        demoOrders: [
          for (final o in s.orders)
            if (o.seed) orderToJson(o, _uid)
        ],
      );

  void _applyPrivate(PrivateState p) {
    state = state.copyWith(
      demoMode: _startsLive ? false : p.demoMode,
      plan: p.plan,
      bizPlan: p.bizPlan,
      creditConsent: p.creditConsent,
      driverOnline: p.driverOnline,
      farmEarned: p.farmEarned,
      driverEarned: p.driverEarned,
      saved: p.saved,
      joined: p.joined,
      driverKyc: p.driverKyc,
      farmKyc: p.farmKyc,
      rerouted: p.rerouted,
      quotes: p.quotes,
      paid: p.paid,
      pins: p.pins,
      stockApplied: p.stockApplied,
      profile: p.profile,
      business: p.business,
      cart: p.cart,
      ledger: p.ledger,
      // Demo content only exists in demo mode.
      products: p.demoMode && !_startsLive ? state.products : state.products.where((x) => x.ownerId != null).toList(),
      orders: !p.demoMode || _startsLive
          ? state.orders.where((o) => !o.seed).toList()
          : p.demoOrders.isEmpty
              ? state.orders
              : [
                  ...state.orders.where((o) => !o.seed),
                  for (final m in p.demoOrders)
                    () {
                      final o = orderFromJson(m, _uid, seed: true);
                      return o.customerIsMe && p.pins[o.id] != null
                          ? o.copyWith(pin: p.pins[o.id])
                          : o;
                    }()
                ],
      cases: p.demoMode ? state.cases : state.cases.where((c) => !_seedCaseIds.contains(c.id)).toList(),
    );
  }

  Future<void> _attach() async {
    try {
      final snap = await _repo.loadPrivate(_uid);
      if (_disposed) return;
      if (snap != null) _applyPrivate(snap);
    } catch (e) {
      debugPrint('market: could not load saved state: $e');
    }
    _ready = true;
    for (final o in state.orders.where((o) => o.seed)) {
      _observe(o);
    }
    _guard(_repo.savePrivate(_uid, _privateOf(state)));
    _subs
      ..add(_repo.watchProducts(_uid).listen(_onProducts, onError: _logErr))
      ..add(_repo.watchOrders(_uid).listen(_onOrders, onError: _logErr))
      ..add(_repo.watchCases(_uid).listen(_onCases, onError: _logErr));
  }

  void _logErr(Object e) => debugPrint('market sync error: $e');

  /// Fire-and-forget writes must never crash the app. Firestore queues them
  /// offline and retries, so a failure here is logged, not thrown.
  void _guard(Future<void> f) => f.catchError((Object e) => _logErr(e));

  // ------------------------------------------------ remote changes in

  void _onProducts(List<Product> remote) {
    if (_disposed) return;
    final ids = {for (final p in remote) p.id};
    final seeds = state.demoMode
        ? state.products.where((p) => p.ownerId == null && !ids.contains(p.id))
        : const <Product>[];
    final pending = state.products.where((p) => p.ownerId != null && !ids.contains(p.id));
    state = state.copyWith(products: [...pending, ...remote, ...seeds]);
  }

  void _onOrders(List<Order> remote) {
    if (_disposed) return;
    final byId = {for (final o in state.orders) o.id: o};
    final changed = <Order>[];
    for (var r in remote) {
      if (r.customerIsMe && r.pin == null && state.pins[r.id] != null) {
        r = r.copyWith(pin: state.pins[r.id]);
      }
      final l = byId[r.id];
      if (l == null || (!l.seed && r.rev > l.rev)) {
        byId[r.id] = r;
        changed.add(r);
      }
    }
    // A job another driver took disappears from this driver's open list.
    final gone = remote.map((o) => o.id).toSet();
    byId.removeWhere((id, o) =>
        !o.seed &&
        !gone.contains(id) &&
        o.status == OrderStatus.findingDriver &&
        o.driverId == null &&
        !o.customerIsMe &&
        !o.farmIsMe &&
        !o.driverIsMe);
    if (changed.isEmpty && byId.length == state.orders.length) return;
    final next = byId.values.toList()..sort((a, b) => b.placed.compareTo(a.placed));
    state = state.copyWith(orders: next);
    for (final o in changed) {
      _observe(o);
    }
  }

  void _onCases(List<ReportCase> remote) {
    if (_disposed) return;
    final ids = {for (final c in remote) c.id};
    final seeds = state.demoMode
        ? state.cases.where((c) => _seedCaseIds.contains(c.id) && !ids.contains(c.id))
        : const <ReportCase>[];
    final pending = state.cases.where((c) => c.mine && !ids.contains(c.id));
    final merged = [
      for (final c in remote)
        (_caseSim[c.id] != null && _caseSim[c.id]!.stage.index > c.stage.index)
            ? _caseSim[c.id]!
            : c
    ];
    state = state.copyWith(cases: [...pending, ...merged, ...seeds]);
  }

  Product product(String id) => state.products.firstWhere((p) => p.id == id);

  // ---------------------------------------------------------- mode

  /// Demo mode keeps the seeded catalogue, simulated neighbours and compressed
  /// timers so a judge can watch the whole loop. Live mode removes all of it:
  /// only real people, real listings and real time.
  void setDemoMode(bool on) {
    if (state.demoMode == on || (on && _startsLive)) return;
    if (on) {
      final d = _demoState();
      final real = state.orders.where((o) => !o.seed);
      state = d.copyWith(
        orders: [...real, ...d.orders],
        products: [...state.products.where((p) => p.ownerId != null), ..._products],
        cases: [...state.cases.where((c) => !_seedCaseIds.contains(c.id)), ..._cases],
      );
    } else {
      state = _stripDemo(state);
    }
  }

  // ---------------------------------------------------------- cart

  /// Adds to the basket. Returns false, and changes nothing, when the basket
  /// holds a different farm's produce: ask the shopper, then [startNewBasket].
  bool add(String id, [int n = 1]) {
    final p = product(id);
    if (!p.buyable) return false;
    if (state.cart.isNotEmpty && state.cartFarm != p.farm) return false;
    final cart = {...state.cart};
    final want = (cart[id] ?? 0) + n;
    cart[id] = p.stock == null ? want : want.clamp(0, p.stock!);
    state = state.copyWith(cart: cart);
    return true;
  }

  /// Empties the basket and starts a new one with this product.
  void startNewBasket(String id, [int n = 1]) {
    state = state.copyWith(cart: const {});
    add(id, n);
  }

  void remove(String id) {
    final cart = {...state.cart};
    final q = (cart[id] ?? 0) - 1;
    if (q <= 0) {
      cart.remove(id);
    } else {
      cart[id] = q;
    }
    state = state.copyWith(cart: cart);
  }

  void loadBundle(MarketAlert a) {
    final cart = {...state.cart};
    for (final id in a.bundle) {
      cart[id] = (cart[id] ?? 0) + 1;
    }
    state = state.copyWith(cart: cart);
  }

  void joinGroup(String id) {
    if (state.joined.contains(id)) return;
    final products = [
      for (final p in state.products)
        if (p.id == id) p.copyWith(groupJoined: p.groupJoined + 1) else p
    ];
    final p = product(id);
    state = state.copyWith(
      products: products,
      joined: {...state.joined, id},
      saved: state.saved + (p.price * 0.1),
    );
  }

  // ---------------------------------------------------------- farmer

  /// Returns a reason when the listing is not allowed yet, else null.
  String? list(Product p) {
    final block = state.listBlock(p.category);
    if (block != null) return block;
    final mine = p.copyWith(
      ownerId: _uid,
      mine: true,
      farm: _farmName,
      delivery: state.profile.delivery,
      deliveryFee: state.profile.deliveryFee,
      place: state.profile.addressLine,
    );
    state = state.copyWith(products: [mine, ...state.products]);
    _guard(_repo.putProduct(mine, _uid));
    return null;
  }

  /// Lists a whole range of products as this farm's own, each with [stock]
  /// units on the shelf. Returns why it could not, or null when it worked.
  String? listRange(List<Product> range, {int stock = 40}) {
    for (final p in range) {
      final r = list(Product(
        id: 'own-${p.id}-$_uid',
        name: p.name,
        emoji: p.emoji,
        category: p.category,
        farm: p.farm,
        km: 1,
        price: p.price,
        unit: p.unit,
        stock: stock,
      ));
      if (r != null) return r;
    }
    return null;
  }

  /// Change one of my own listings: restock, reprice, or pause it.
  void updateProduct(String id, {int? stock, double? price, bool? available, bool? rescue}) {
    final cur = state.products.where((p) => p.id == id && p.mine);
    if (cur.isEmpty) return;
    final next = cur.first.copyWith(
      stock: stock,
      price: price,
      available: available,
      rescue: rescue,
      // A rescue price shows the old price struck through.
      wasPrice: (price != null && price < cur.first.price) ? cur.first.price : null,
      clearWasPrice: price != null && price >= cur.first.price,
    );
    state = state.copyWith(products: [for (final p in state.products) if (p.id == id) next else p]);
    _guard(_repo.putProduct(next, _uid));
  }

  /// A farmer's shelf shrinks when an order for their produce arrives. Done on
  /// the farmer's phone, once per order, because only the owner may edit a
  /// listing.
  void _takeStock(Order o) {
    if (state.stockApplied.contains(o.id)) return;
    var products = state.products;
    for (final l in o.lines.where((l) => l.mine && l.productId != null)) {
      products = [
        for (final p in products)
          if (p.id == l.productId && p.stock != null)
            () {
              final next = p.copyWith(stock: (p.stock! - l.qty).clamp(0, 1 << 30));
              _guard(_repo.putProduct(next, _uid));
              return next;
            }()
          else
            p
      ];
    }
    state = state.copyWith(products: products, stockApplied: {...state.stockApplied, o.id});
  }

  void packOrder(String id) {
    final cur = state.orderById(id);
    if (cur != null && cur.selfDelivery && cur.farmIsMe) {
      // The farm brings it itself: no driver queue. The farmer collects it,
      // then enters the buyer's PIN at the door.
      _patch(
          id,
          (o) => o.copyWith(
              status: OrderStatus.assigned,
              driver: _farmName,
              driverIsMe: true,
              driverId: _uid,
              commission: state.plan.commission));
    } else {
      _patch(id, (o) => o.copyWith(
          status: OrderStatus.findingDriver, commission: state.plan.commission));
    }
    _observe(state.orderById(id)!);
  }

  // ------------------------------------------------------------- hub

  /// The farm says the order is at the hub. Only the farm that sells it, and
  /// only once it has packed it.
  bool dropAtHub(String id) {
    final o = state.orderById(id);
    if (o == null || !o.farmIsMe || o.hubStage != 'toHub' || o.status == OrderStatus.newOrder) return false;
    _patch(id, (x) => x.copyWith(hubStage: 'droppedOff'));
    return true;
  }

  /// Hub staff check an order in by typing the code on its packing slip.
  bool hubReceive(String id, String code) {
    final o = state.orderById(id);
    if (o == null || o.hubStage != 'droppedOff' || code.trim() != o.hubCode) return false;
    _patch(id, (x) => x.copyWith(hubStage: 'received'));
    return true;
  }

  /// Hub staff sort the order into the last-mile bin. It becomes a job.
  bool hubRelease(String id) {
    final o = state.orderById(id);
    if (o == null || o.hubStage != 'received') return false;
    _patch(id, (x) => x.copyWith(hubStage: 'released'));
    _observe(state.orderById(id)!);
    return true;
  }

  /// Demo only: a pretend farm drop-off and hub desk, slow enough for a judge
  /// to act first. Each step does nothing if a person already did it.
  void _simHub(String id) {
    void step(int secs, String from, String to) => _later(Duration(seconds: secs), () {
          final o = state.orderById(id);
          if (o == null || o.hubStage != from) return;
          _patch(id, (x) => x.copyWith(hubStage: to));
          if (to == 'released') _observe(state.orderById(id)!);
        });
    step(8, 'toHub', 'droppedOff');
    step(20, 'droppedOff', 'received');
    step(32, 'received', 'released');
  }

  /// Saves personal and farm-store details. A farm's public name and how it
  /// delivers follow it onto every product it sells.
  void updateProfile(ProfileSettings p) {
    state = state.copyWith(profile: p);
    final farm = _farmName;
    final next = <Product>[];
    for (final x in state.products) {
      if (!x.mine) {
        next.add(x);
        continue;
      }
      final u = x.copyWith(farm: farm, delivery: p.delivery, deliveryFee: p.deliveryFee, place: p.addressLine);
      next.add(u);
      _guard(_repo.putProduct(u, _uid));
    }
    state = state.copyWith(products: next);
  }

  /// Registers the farm as a business on Nolifa Drop. Verification and the
  /// monthly plan come next; selling needs all three ([MarketState.canSell]).
  void registerBusiness({String kind = 'individual', String regNumber = ''}) {
    state = state.copyWith(
        business: state.business.copyWith(registered: true, kind: kind, regNumber: regNumber));
  }

  /// Picks a plan and pays its monthly fee, which includes support.
  void setPlan(Plan p) {
    state = state.copyWith(plan: p, business: state.business.copyWith(planPaid: true));
    _ledger(LedgerEntry(
        '${p.label} plan',
        'Monthly platform fee and support. The app does not collect it yet: Nolifa confirms payment and switches the plan on.',
        -p.price.toDouble(),
        LedgerKind.fee));
  }

  /// Geo-tagged photos of the land, crop and water source are in. Opens
  /// selling with limits while the inspection is arranged.
  void submitLandEvidence() {
    state = state.copyWith(
        business: state.business.copyWith(
            evidenceDone: true,
            provisionalSince:
                state.business.provisionalSince ?? DateTime.now().millisecondsSinceEpoch));
  }

  /// Books the on-site check by the chosen route. The visit date is the
  /// route's usual wait; a real backend replaces it with the inspector's slot.
  void requestInspection(InspectionRoute route) {
    state = state.copyWith(
        business: state.business.copyWith(
            inspection: InspectionStatus.scheduled,
            route: route,
            visitOn: DateTime.now().add(Duration(days: route.waitDays)).millisecondsSinceEpoch));
  }

  /// The inspector's result. In demo mode a button calls this so a judge can
  /// see both outcomes. Live, only the inspection backend writes it.
  void recordInspection({required bool passed}) {
    state = state.copyWith(
        business: state.business.copyWith(
            inspection: passed ? InspectionStatus.passed : InspectionStatus.failed));
  }

  /// Marks the phone number as checked. The app has already compared the code
  /// the person typed; a real backend sends and checks the SMS itself and
  /// allows one verified number per account.
  void verifyPhone(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return;
    state = state.copyWith(profile: state.profile.copyWith(phone: p, verifiedPhone: p));
  }

  void setConsent(bool v) => state = state.copyWith(creditConsent: v);

  // ---------------------------------------------------------- radar

  void setBizPlan(BizPlan p) => state = state.copyWith(bizPlan: p);

  /// Moves a supplier's volume to backups while the farm is cleared. The farm
  /// is not delisted: this is a temporary reroute, lifted when the case closes.
  void reroute(String supplierId, bool on) {
    final r = {...state.rerouted};
    on ? r.add(supplierId) : r.remove(supplierId);
    state = state.copyWith(rerouted: r);
  }

  void requestQuote(String altId) {
    state = state.copyWith(quotes: {...state.quotes, altId});
    _ledger(LedgerEntry('Quote requested',
        alternatives.firstWhere((a) => a.id == altId).name, 0, LedgerKind.fee));
  }

  // ---------------------------------------------- verification of people

  void completeKyc(KycRole role, String step) {
    if (role == KycRole.driver) {
      state = state.copyWith(driverKyc: {...state.driverKyc, step});
    } else {
      state = state.copyWith(farmKyc: {...state.farmKyc, step});
    }
  }

  // ------------------------------------- verification of outbreak reports

  /// A farmer files a case. It is AI checked immediately, but only reaches
  /// other farms once neighbours confirm it or a vet verifies it.
  String submitReport(String title, String emoji, String area) {
    final id = 'c-${_uid.hashCode.abs().toRadixString(36)}-${++_case}';
    final c = ReportCase(
        id: id,
        emoji: emoji,
        title: title,
        area: area,
        stage: ReportStage.aiChecked,
        confirmations: 0,
        aiConfidence: 78,
        reporterId: _uid,
        mine: true);
    state = state.copyWith(cases: [c, ...state.cases]);
    _guard(_repo.putCase(c, _uid));
    if (state.demoMode) {
      _later(const Duration(seconds: 5), () => _advanceCase(id, 1, ReportStage.aiChecked));
      _later(const Duration(seconds: 10), () => _advanceCase(id, 2, ReportStage.corroborated));
      _later(const Duration(seconds: 18), () => _advanceCase(id, 3, ReportStage.vetVerified));
    }
    return id;
  }

  /// Returns false when this person may not confirm (not a verified farmer).
  bool confirmCase(String id) {
    if (!state.canConfirmOutbreaks) return false;
    final c = state.cases.firstWhere((c) => c.id == id);
    if (c.confirmedBy.contains(_uid) || c.mine) return true;
    final n = c.confirmations + 1;
    final stage = (n >= 2 && c.stage == ReportStage.aiChecked) ? ReportStage.corroborated : c.stage;
    state = state.copyWith(cases: [
      for (final x in state.cases)
        if (x.id == id) x.copyWith(confirmations: n, stage: stage, confirmedBy: [...x.confirmedBy, _uid]) else x
    ]);
    _guard(_repo.confirmCase(id, _uid));
    return true;
  }

  void _advanceCase(String id, int confirmations, ReportStage stage) {
    if (_disposed) return;
    ReportCase? updated;
    state = state.copyWith(cases: [
      for (final c in state.cases)
        if (c.id == id) (updated = c.copyWith(confirmations: confirmations, stage: stage)) else c
    ]);
    if (updated == null) return;
    if (_repo.shared) {
      // The server only lets neighbours and vets move a case forward, so the
      // demo's fast-forward is kept on this device.
      _caseSim[id] = updated;
    } else {
      _guard(_repo.putCase(updated, _uid));
    }
  }

  // ---------------------------------------------------------- checkout

  String _newId() {
    const a = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    return 'UD-${List.generate(5, (_) => a[_rng.nextInt(a.length)]).join()}';
  }

  /// Places the order. [fromStock] says the goods are already in the Nolifa
  /// warehouse, so a hub order skips the farm drop-off.
  String place(PayMethod method, {bool fromStock = false}) {
    final lines = [
      for (final e in state.cart.entries)
        () {
          final p = product(e.key);
          return OrderLine(p.name, p.emoji, e.value, p.price,
              mine: p.mine, ownerId: p.ownerId, productId: p.id);
        }()
    ];
    final first = product(state.cart.keys.first);
    final id = _newId();
    final pin = '${1000 + _rng.nextInt(9000)}';
    final saved = state.cart.keys.any(state.joined.contains) ? state.deliveryFee : 0.0;
    // A real farm has to pack the order first. Demo farms and your own
    // produce go straight to the driver queue.
    final needsFarmer = first.ownerId != null && first.ownerId != _uid;
    final selfDelivery = first.delivery == DeliveryMode.self;
    final plan = state.deliveryPlan!;
    final order = Order(
      id: id,
      lines: lines,
      deliveryFee: state.deliveryFee,
      serviceFee: state.serviceFee,
      commission: state.cartCommission,
      method: method,
      status: needsFarmer ? OrderStatus.newOrder : OrderStatus.findingDriver,
      customer: _display,
      pickup: first.farm,
      dropArea: state.profile.addressLine.isEmpty ? (state.demoMode ? 'Umlazi' : 'Your street') : state.profile.addressLine,
      selfDelivery: selfDelivery,
      route: plan.route.name,
      hub: plan.route == DeliveryRoute.hub ? plan.hub?.name : null,
      distanceKm: double.parse(plan.farmKm.toStringAsFixed(1)),
      hubStage: plan.route == DeliveryRoute.hub ? (fromStock ? 'received' : 'toHub') : null,
      fromStock: plan.route == DeliveryRoute.hub && fromStock,
      pin: pin,
      pinHash: hashPin(id, pin),
      placed: DateTime.now(),
      customerIsMe: true,
      customerId: _uid,
      farmerId: first.ownerId,
      farmIsMe: first.ownerId == _uid,
      // Orders from demo farms are a local simulation and are never synced.
      seed: first.ownerId == null,
    );
    state = state.copyWith(
      orders: [order, ...state.orders],
      cart: const {},
      pins: {...state.pins, id: pin},
      saved: state.saved + saved,
    );
    _putNew(order, pin);
    _ledger(LedgerEntry(
        method == PayMethod.cash ? 'Cash on delivery' : 'Held in escrow',
        '$id · ${method.label}',
        method == PayMethod.cash ? 0 : -order.total,
        LedgerKind.held));
    _observe(order);
    return id;
  }

  // ---------------------------------------------------------- driver

  void toggleOnline() {
    if (!state.driverVerified && !state.driverOnline) return;
    state = state.copyWith(driverOnline: !state.driverOnline);
  }

  /// Takes a job. On a shared backend the claim is atomic: if another driver
  /// got there first, this one is rolled back.
  void accept(String id) {
    final o = state.orderById(id);
    if (o == null) return;
    if (o.hubStage != null && o.hubStage != 'released') return; // still at the hub
    final claimOnServer = _repo.shared && !o.seed;
    // On a shared backend only the atomic claim may write, so a driver who
    // loses the race can never overwrite the winner.
    _patch(
        id,
        (o) => o.copyWith(
            status: OrderStatus.assigned, driver: _name, driverIsMe: true, driverId: _uid),
        persist: !claimOnServer);
    if (claimOnServer) {
      _guard(_repo.claimJob(id, _uid, _name).then((ok) {
        if (!ok && !_disposed) {
          state = state.copyWith(orders: [
            for (final x in state.orders)
              if (x.id == id && x.driverIsMe) o else x
          ]);
        }
      }));
    }
  }

  /// Takes a whole batch of jobs at once. On a shared backend it is one atomic
  /// claim: if any job was taken first, none is taken and the driver is told.
  Future<bool> acceptBatch(List<String> ids) async {
    final jobs = [for (final id in ids) if (state.orderById(id) != null) state.orderById(id)!];
    if (jobs.length != ids.length || jobs.isEmpty) return false;
    if (jobs.any((o) => o.hubStage != null && o.hubStage != 'released')) return false;
    final onServer = _repo.shared && !jobs.any((o) => o.seed);
    if (onServer) {
      final ok = await _repo.claimBatch(ids, _uid, _name);
      if (!ok || _disposed) return false;
    }
    state = state.copyWith(orders: [
      for (final o in state.orders)
        if (ids.contains(o.id))
          o.copyWith(status: OrderStatus.assigned, driver: _name, driverIsMe: true, driverId: _uid, rev: o.rev + (onServer ? 1 : 0))
        else
          o
    ]);
    if (!onServer) {
      for (final id in ids) {
        final o = state.orderById(id);
        if (o != null) _guard(_repo.putOrder(o, _uid));
      }
    }
    return true;
  }

  /// Driver collects the goods. The photo taken at pickup is stored as proof.
  void pickedUp(String id) =>
      _patch(id, (o) => o.copyWith(status: OrderStatus.pickedUp, pickupProof: true));

  /// Delivery only completes when the buyer's 4-digit PIN is entered.
  bool deliverWithPin(String id, String pin) => tryPin(id, pin).delivered;

  /// Checks a PIN and counts wrong tries. After [maxPinAttempts] wrong tries
  /// the order locks, a dispute opens and the money stays frozen until a
  /// mediator rules, so the PIN cannot be guessed.
  /// Checks the PIN. On a shared backend the server does it and counts the
  /// tries, so a driver cannot work the PIN out from what their phone holds.
  Future<PinResult> checkPin(String id, String pin) async {
    final o = state.orderById(id);
    if (o == null) return const PinResult(PinOutcome.locked, 0);
    if (!_repo.shared || o.seed) return tryPin(id, pin);
    try {
      final r = await _repo.deliverWithPin(id, pin);
      final left = (r['attemptsLeft'] as num?)?.toInt() ?? 0;
      return switch (r['outcome']) {
        'delivered' => PinResult(PinOutcome.delivered, left),
        'wrong' => PinResult(PinOutcome.wrong, left),
        _ => const PinResult(PinOutcome.locked, 0),
      };
    } catch (e) {
      _logErr(e);
      return const PinResult(PinOutcome.error, 0);
    }
  }

  PinResult tryPin(String id, String pin) {
    final o = state.orderById(id);
    if (o == null) return const PinResult(PinOutcome.locked, 0);
    if (o.disputed || o.pinAttempts >= maxPinAttempts) return const PinResult(PinOutcome.locked, 0);
    if (o.pinMatches(pin)) {
      _markDelivered(id);
      return const PinResult(PinOutcome.delivered, maxPinAttempts);
    }
    final used = o.pinAttempts + 1;
    _patch(id, (x) => x.copyWith(pinAttempts: used));
    if (used >= maxPinAttempts) {
      _startDispute(id, DisputeReason.pinLocked,
          'The delivery PIN was entered wrongly $maxPinAttempts times, so the order was locked.');
      return const PinResult(PinOutcome.locked, 0);
    }
    return PinResult(PinOutcome.wrong, maxPinAttempts - used);
  }

  // ------------------------------------------------- buyer protection

  /// Buyer confirms everything is fine, so the money is released at once.
  void confirmReceived(String id, int rating) {
    // The rating travels in the same write as the release.
    _patch(id, (o) => o.copyWith(rating: rating), persist: false);
    _release(id);
  }

  bool canDispute(Order o) =>
      o.customerIsMe &&
      o.dispute == null &&
      !o.released &&
      (o.status == OrderStatus.pickedUp || o.status == OrderStatus.delivered);

  /// Freezes the money in escrow and starts the mediation clock.
  void openDispute(String id, DisputeReason reason, String note) {
    final o = state.orderById(id);
    if (o == null || !canDispute(o)) return;
    _startDispute(id, reason, note);
  }

  void _startDispute(String id, DisputeReason reason, String note) {
    final now = DateTime.now();
    _patch(
        id,
        (o) => o.copyWith(
            dispute: Dispute(
          reason: reason,
          note: note,
          stage: DisputeStage.open,
          timeline: [
            ('Dispute opened: ${reason.label}', now),
            ('Payment frozen in escrow. Nobody is paid yet', now),
          ],
        )));
    _observe(state.orderById(id)!);
  }

  Outcome _outcomeFor(DisputeReason r) => switch (r) {
        DisputeReason.notDelivered => Outcome.fullRefund,
        DisputeReason.damaged || DisputeReason.wrongItems => Outcome.partialRefund,
        DisputeReason.late || DisputeReason.driverConduct => Outcome.deliveryRefund,
        // A guessed PIN is not a delivery. Refund while a person looks into it.
        DisputeReason.pinLocked => Outcome.fullRefund,
      };

  /// What a mediator does: decide the case, then settle the money. In demo
  /// mode this runs by itself; live cases wait for a person.
  void resolveDispute(String id, Outcome outcome) {
    final cur = state.orderById(id);
    if (cur?.dispute == null || cur!.settledByDispute) return;
    _patch(id, (o) => o.copyWith(
        dispute: o.dispute!.copyWith(
            stage: DisputeStage.resolved,
            outcome: outcome,
            event: 'Resolved: ${o.dispute!.reason.remedy}')));
    _settle(id);
  }

  // ---------------------------------------------------------- internals

  void _patch(String id, Order Function(Order) f, {bool persist = true}) {
    Order? next;
    state = state.copyWith(orders: [
      for (final o in state.orders)
        if (o.id == id) (next = f(o).copyWith(rev: o.rev + 1)) else o
    ]);
    if (next != null && persist) _put(next);
  }

  /// A new order goes to the server to be checked. If the server refuses it
  /// (a price changed, a product ran out), the order is taken back off the phone
  /// and the buyer is told why.
  void _putNew(Order o, String pin) {
    if (o.seed) return;
    () async {
      try {
        await _repo.placeOrder(o, _uid, pin);
      } catch (e) {
        if (_disposed) return;
        _logErr(e);
        state = state.copyWith(
          orders: [for (final x in state.orders) if (x.id != o.id) x],
          pins: {for (final p in state.pins.entries) if (p.key != o.id) p.key: p.value},
        );
        ref.read(placeErrorProvider.notifier).state = _placeMessage(e);
      }
    }();
  }

  String _placeMessage(Object e) {
    if (e is PostgrestException && (e.code == 'P0005' || e.code == 'P0001' || e.code == '42501')) return e.message;
    return friendlyError(e, doing: 'place that order');
  }

  void _put(Order o) {
    if (o.seed) return; // demo-only orders never leave the device
    _guard(_repo.putOrder(o, _uid));
  }

  void _ledger(LedgerEntry e) {
    state = state.copyWith(ledger: [e, ...state.ledger]);
  }

  void _later(Duration d, void Function() f) {
    _timers.add(Timer(d, () {
      if (!_disposed) f();
    }));
  }

  /// Looks at an order and starts whatever should happen next. Safe to call
  /// repeatedly: each flow runs once per order. Used for local changes and for
  /// orders that arrive from another phone, so every device does its own part.
  void _observe(Order o) {
    if (o.farmIsMe && !o.seed && o.status != OrderStatus.delivered && !o.released) _takeStock(o);
    if (o.released && !state.paid.contains(o.id)) _payouts(o);
    if (o.status == OrderStatus.delivered &&
        !o.released &&
        o.dispute == null &&
        _releasing.add(o.id)) {
      // The buyer's own clock may be compressed in demo mode. Everyone else
      // waits the real 2 hours, which is all the server lets them release at.
      final fast = state.demoMode && (o.seed || o.customerIsMe);
      _later(fast ? protectionWindow : const Duration(hours: 2), () {
        final cur = state.orderById(o.id);
        if (cur == null || cur.released || cur.dispute != null) {
          _releasing.remove(o.id);
          return;
        }
        _release(o.id);
      });
    }
    final involved = o.customerIsMe || o.farmIsMe;
    // Only device-only demo orders are simulated. Real orders wait for real people.
    final atHub = o.hubStage != null && o.hubStage != 'released';
    if (state.demoMode && o.seed && involved && atHub && o.status == OrderStatus.findingDriver && _hubSimmed.add(o.id)) {
      _simHub(o.id);
    }
    if (state.demoMode && o.seed && involved && !atHub) {
      if (o.status == OrderStatus.findingDriver && o.driver == null && _simmed.add(o.id)) {
        _simDriver(o.id);
      } else if ((o.status == OrderStatus.assigned || o.status == OrderStatus.pickedUp) &&
          (o.driver == _simDriverName || (o.selfDelivery && !o.farmIsMe)) &&
          _simmed.add(o.id)) {
        _simDrive(o.id);
      }
    }
    final d = o.dispute;
    if (state.demoMode &&
        o.seed &&
        d != null &&
        d.stage != DisputeStage.resolved &&
        _disputing.add(o.id)) {
      _simMediator(o.id);
    }
  }

  /// Demo only: a neighbour driver picks up the job and carries it through.
  void _simDriver(String id) {
    _later(const Duration(seconds: 5), () async {
      final o = state.orderById(id);
      if (o == null || o.driver != null) return;
      if (_repo.shared && !o.seed) {
        final ok = await _repo.claimJob(id, 'sim-driver', _simDriverName);
        if (!ok || _disposed) return;
      }
      final cur = state.orderById(id);
      // A demo farm that delivers itself sends its own person, not a Nolifa driver.
      final who = (cur?.selfDelivery ?? false) ? cur!.pickup : _simDriverName;
      if (cur == null || (cur.driver != null && cur.driver != who)) return;
      _patch(id, (o) => o.copyWith(
          status: OrderStatus.assigned, driver: who, driverId: 'sim-driver'));
      _simDrive(id, fromAssigned: true);
    });
  }

  void _simDrive(String id, {bool fromAssigned = false}) {
    void deliver() {
      _later(const Duration(seconds: 9), () {
        if (state.orderById(id)?.status == OrderStatus.pickedUp) _markDelivered(id);
      });
    }

    final status = state.orderById(id)?.status;
    if (status == OrderStatus.pickedUp) {
      deliver();
      return;
    }
    _later(const Duration(seconds: 5), () {
      if (state.orderById(id)?.status == OrderStatus.assigned) {
        _patch(id, (o) => o.copyWith(status: OrderStatus.pickedUp, pickupProof: true));
      }
      deliver();
    });
  }

  void _simMediator(String id) {
    final stage = state.orderById(id)?.dispute?.stage;
    if (stage == DisputeStage.open) {
      _later(const Duration(seconds: 5), () {
        final cur = state.orderById(id);
        if (cur?.dispute == null || cur!.dispute!.stage != DisputeStage.open) return;
        _patch(id, (o) => o.copyWith(
            dispute: o.dispute!.copyWith(
                stage: DisputeStage.review,
                event: 'Mediator assigned. Checking GPS trail, pickup photo and PIN log')));
      });
    }
    _later(Duration(seconds: stage == DisputeStage.open ? 12 : 7), () {
      final cur = state.orderById(id);
      if (cur?.dispute == null) return;
      resolveDispute(id, _outcomeFor(cur!.dispute!.reason));
    });
  }

  void _markDelivered(String id) {
    _patch(id, (o) => o.copyWith(status: OrderStatus.delivered, deliveredAt: DateTime.now()));
    _observe(state.orderById(id)!);
  }

  void _release(String id) {
    final o = state.orderById(id);
    if (o == null || o.released || o.disputed) return;
    _patch(id, (o) => o.copyWith(released: true));
    _observe(state.orderById(id)!);
  }

  void _settle(String id) {
    final o = state.orderById(id);
    if (o == null || o.released) return;
    _patch(id, (o) => o.copyWith(released: true));
    _observe(state.orderById(id)!);
  }

  /// Turns a finished order into ledger lines and balances: who is paid what.
  /// Each device runs this once per order for its own role, and remembers it
  /// did, so a restart or a repeated sync never pays anyone twice.
  void _payouts(Order o) {
    if (state.paid.contains(o.id)) return;
    final now = DateTime.now();
    var farm = state.farmEarned;
    var driver = state.driverEarned;
    final entries = <LedgerEntry>[];

    if (o.customerIsMe) {
      if (o.refund > 0) {
        entries.add(LedgerEntry('Refund', '${o.id} · ${o.dispute!.reason.remedy}',
            o.refund, LedgerKind.refund, now));
      } else {
        entries.add(LedgerEntry('Escrow released',
            '${o.id} · paid to the farm${o.selfDelivery ? '' : ' and driver'}', 0,
            LedgerKind.payout, now));
      }
    }
    if (o.mySalesGross > 0 && o.farmFactor > 0) {
      farm += o.mySalesNet;
      final pct = (o.commission * 100).round();
      entries.add(LedgerEntry(
          'Sale payout',
          '${o.id} · ${rand0(o.mySalesGross * o.farmFactor)} less $pct% commission',
          o.mySalesNet,
          LedgerKind.payout,
          now));
    }
    if (o.farmIsMe && o.selfDeliveryPay > 0) {
      farm += o.selfDeliveryPay;
      entries.add(LedgerEntry('Delivery by you', '${o.id} · you kept the delivery fee',
          o.selfDeliveryPay, LedgerKind.payout, now));
    }
    if (o.driverIsMe && o.driverPay > 0) {
      driver += o.driverPay;
      entries.add(LedgerEntry('Delivery payout',
          '${o.id} · R12 plus R2.50 a km', o.driverPay,
          LedgerKind.driver, now));
    }
    state = state.copyWith(
      farmEarned: farm,
      driverEarned: driver,
      paid: {...state.paid, o.id},
      ledger: [...entries.reversed, ...state.ledger],
    );
  }
}

String rand0(double v) => 'R${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

final marketProvider = NotifierProvider<MarketStore, MarketState>(MarketStore.new);

/// True when orders and listings are shared between phones.
final marketSharedProvider =
    Provider<bool>((ref) => ref.watch(marketRepositoryProvider).shared);
