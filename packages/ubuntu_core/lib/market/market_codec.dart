import 'market_models.dart';

/// JSON for everything that is saved or synced.
///
/// Roles are stored as user ids (customerId, farmerId, driverId). Each device
/// turns them back into "is this me?" flags when it decodes, so the same
/// document reads correctly on the buyer's, the farmer's and the driver's phone.

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// -------------------------------------------------------------- product

Map<String, dynamic> productToJson(Product p) => {
      'id': p.id,
      'name': p.name,
      'emoji': p.emoji,
      'category': p.category.name,
      'farm': p.farm,
      'km': p.km,
      'price': p.price,
      'wasPrice': p.wasPrice,
      'unit': p.unit,
      'groupTarget': p.groupTarget,
      'groupJoined': p.groupJoined,
      'rescue': p.rescue,
      'ownerId': p.ownerId,
      'stock': p.stock,
      'available': p.available,
      'delivery': p.delivery.name,
      'deliveryFee': p.deliveryFee,
    };

Product productFromJson(Map<String, dynamic> m, String uid) => Product(
      id: m['id'] as String,
      name: m['name'] as String,
      emoji: m['emoji'] as String? ?? '🧺',
      category: _enum(Category.values, m['category'], Category.veg),
      farm: m['farm'] as String? ?? 'Farm',
      km: (m['km'] as num?)?.toDouble() ?? 0,
      price: (m['price'] as num).toDouble(),
      wasPrice: (m['wasPrice'] as num?)?.toDouble(),
      unit: m['unit'] as String? ?? 'pack',
      groupTarget: (m['groupTarget'] as num?)?.toInt() ?? 0,
      groupJoined: (m['groupJoined'] as num?)?.toInt() ?? 0,
      rescue: m['rescue'] as bool? ?? false,
      ownerId: m['ownerId'] as String?,
      stock: (m['stock'] as num?)?.toInt(),
      available: m['available'] as bool? ?? true,
      delivery: DeliveryMode.values.firstWhere((d) => d.name == m['delivery'],
          orElse: () => DeliveryMode.platform),
      deliveryFee: (m['deliveryFee'] as num?)?.toDouble(),
      mine: m['ownerId'] != null && m['ownerId'] == uid,
    );

// ---------------------------------------------------------------- order

Map<String, dynamic> _lineToJson(OrderLine l, {bool seed = false}) => {
      if (seed) 'mine': l.mine, // demo orders have no real owner ids
      'name': l.name,
      'emoji': l.emoji,
      'qty': l.qty,
      'price': l.price,
      'ownerId': l.ownerId,
      'productId': l.productId,
    };

OrderLine _lineFromJson(Map<String, dynamic> m, String uid, {bool seed = false}) => OrderLine(
      m['name'] as String,
      m['emoji'] as String? ?? '🧺',
      (m['qty'] as num).toInt(),
      (m['price'] as num).toDouble(),
      ownerId: m['ownerId'] as String?,
      productId: m['productId'] as String?,
      mine: (seed && m['mine'] == true) || (m['ownerId'] != null && m['ownerId'] == uid),
    );

Map<String, dynamic> _disputeToJson(Dispute d) => {
      'reason': d.reason.name,
      'note': d.note,
      'stage': d.stage.name,
      'outcome': d.outcome?.name,
      'timeline': [
        for (final e in d.timeline) {'t': e.$1, 'at': e.$2.millisecondsSinceEpoch}
      ],
    };

Dispute _disputeFromJson(Map<String, dynamic> m) => Dispute(
      reason: _enum(DisputeReason.values, m['reason'], DisputeReason.notDelivered),
      note: m['note'] as String? ?? '',
      stage: _enum(DisputeStage.values, m['stage'], DisputeStage.open),
      outcome: m['outcome'] == null ? null : _enum(Outcome.values, m['outcome'], Outcome.fullRefund),
      timeline: [
        for (final e in (m['timeline'] as List? ?? const []))
          (
            (e as Map)['t'] as String,
            DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt()),
          )
      ],
    );

/// Participants lets Firestore find "my orders" with one array-contains query.
Map<String, dynamic> orderToJson(Order o, String uid) {
  final customerId = o.customerIsMe ? uid : o.customerId;
  final farmerId = o.farmIsMe ? uid : o.farmerId;
  final driverId = o.driverIsMe ? uid : o.driverId;
  return {
    'id': o.id,
    'lines': [for (final l in o.lines) _lineToJson(l, seed: o.seed)],
    'deliveryFee': o.deliveryFee,
    'serviceFee': o.serviceFee,
    'commission': o.commission,
    'method': o.method.name,
    'status': o.status.name,
    'customer': o.customer,
    'pickup': o.pickup,
    'dropArea': o.dropArea,
    'pinHash': o.pinHash ?? (o.pin == null ? null : hashPin(o.id, o.pin!)),
    // Demo orders never leave this device, so keeping their PIN is safe.
    if (o.seed && o.pin != null) 'pin': o.pin,
    'driver': o.driver,
    'customerId': customerId,
    'farmerId': farmerId,
    'driverId': driverId,
    'participants': [
      for (final id in {customerId, farmerId, driverId})
        if (id != null) id
    ],
    'pickupProof': o.pickupProof,
    'pinAttempts': o.pinAttempts,
    'released': o.released,
    'placed': o.placed.millisecondsSinceEpoch,
    'deliveredAt': o.deliveredAt?.millisecondsSinceEpoch,
    'dispute': o.dispute == null ? null : _disputeToJson(o.dispute!),
    'rating': o.rating,
    'selfDelivery': o.selfDelivery,
    'rev': o.rev,
  };
}

Order orderFromJson(Map<String, dynamic> m, String uid, {bool seed = false}) => Order(
      id: m['id'] as String,
      lines: [
        for (final l in (m['lines'] as List)) _lineFromJson(Map<String, dynamic>.from(l as Map), uid, seed: seed)
      ],
      deliveryFee: (m['deliveryFee'] as num).toDouble(),
      serviceFee: (m['serviceFee'] as num?)?.toDouble() ?? 0,
      commission: (m['commission'] as num?)?.toDouble() ?? 0.08,
      method: _enum(PayMethod.values, m['method'], PayMethod.fnbPay),
      status: _enum(OrderStatus.values, m['status'], OrderStatus.findingDriver),
      customer: m['customer'] as String? ?? 'Customer',
      pickup: m['pickup'] as String? ?? 'Farm',
      dropArea: m['dropArea'] as String? ?? '',
      pin: seed ? m['pin'] as String? : null,
      pinHash: m['pinHash'] as String?,
      driver: m['driver'] as String?,
      customerId: m['customerId'] as String?,
      farmerId: m['farmerId'] as String?,
      driverId: m['driverId'] as String?,
      customerIsMe: m['customerId'] != null && m['customerId'] == uid,
      farmIsMe: m['farmerId'] != null && m['farmerId'] == uid,
      driverIsMe: m['driverId'] != null && m['driverId'] == uid,
      pickupProof: m['pickupProof'] as bool? ?? false,
      pinAttempts: (m['pinAttempts'] as num?)?.toInt() ?? 0,
      released: m['released'] as bool? ?? false,
      placed: DateTime.fromMillisecondsSinceEpoch((m['placed'] as num).toInt()),
      deliveredAt: m['deliveredAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((m['deliveredAt'] as num).toInt()),
      dispute: m['dispute'] == null
          ? null
          : _disputeFromJson(Map<String, dynamic>.from(m['dispute'] as Map)),
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      rev: (m['rev'] as num?)?.toInt() ?? 0,
      selfDelivery: m['selfDelivery'] as bool? ?? false,
      seed: seed,
    );

// ----------------------------------------------------------------- case

Map<String, dynamic> caseToJson(ReportCase c, String uid) => {
      'id': c.id,
      'emoji': c.emoji,
      'title': c.title,
      'area': c.area,
      'stage': c.stage.name,
      'confirmations': c.confirmations,
      'aiConfidence': c.aiConfidence,
      'reporterId': c.mine ? uid : c.reporterId,
      'confirmedBy': c.confirmedBy,
    };

ReportCase caseFromJson(Map<String, dynamic> m, String uid) => ReportCase(
      id: m['id'] as String,
      emoji: m['emoji'] as String? ?? '🚩',
      title: m['title'] as String,
      area: m['area'] as String? ?? '',
      stage: _enum(ReportStage.values, m['stage'], ReportStage.submitted),
      confirmations: (m['confirmations'] as num?)?.toInt() ?? 0,
      aiConfidence: (m['aiConfidence'] as num?)?.toInt() ?? 0,
      reporterId: m['reporterId'] as String?,
      confirmedBy: [for (final x in (m['confirmedBy'] as List? ?? const [])) x as String],
      mine: m['reporterId'] != null && m['reporterId'] == uid,
    );

// --------------------------------------------------------------- ledger

Map<String, dynamic> ledgerToJson(LedgerEntry e) => {
      'title': e.title,
      'sub': e.sub,
      'amount': e.amount,
      'kind': e.kind.name,
      'at': e.time.millisecondsSinceEpoch,
    };

LedgerEntry ledgerFromJson(Map<String, dynamic> m) => LedgerEntry(
      m['title'] as String,
      m['sub'] as String? ?? '',
      (m['amount'] as num).toDouble(),
      _enum(LedgerKind.values, m['kind'], LedgerKind.fee),
      DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
    );

// ------------------------------------------------ per-user private state

/// Everything private to one user: money balances, plan, checks, ledger and
/// the cart. Never readable by other users.
class PrivateState {
  final bool demoMode;
  final Plan plan;
  final BizPlan bizPlan;
  final bool creditConsent;
  final bool driverOnline;
  final double farmEarned;
  final double driverEarned;
  final double saved;
  final Set<String> joined;
  final Set<String> driverKyc;
  final Set<String> farmKyc;
  final Set<String> rerouted;
  final Set<String> quotes;
  final Set<String> paid; // orders already turned into payouts on this device
  final Map<String, String> pins; // delivery PINs of my own orders
  final Set<String> stockApplied; // orders whose stock I have already taken off my shelf
  final ProfileSettings profile;
  final BusinessProfile business;
  final Map<String, int> cart;
  final List<LedgerEntry> ledger;
  final List<Map<String, dynamic>> demoOrders; // device-only demo orders, saved here

  const PrivateState({
    required this.demoMode,
    required this.plan,
    required this.bizPlan,
    required this.creditConsent,
    required this.driverOnline,
    required this.farmEarned,
    required this.driverEarned,
    required this.saved,
    required this.joined,
    required this.driverKyc,
    required this.farmKyc,
    required this.rerouted,
    required this.quotes,
    required this.paid,
    required this.pins,
    this.stockApplied = const {},
    this.profile = const ProfileSettings(),
    this.business = const BusinessProfile(),
    required this.cart,
    required this.ledger,
    this.demoOrders = const [],
  });

  Map<String, dynamic> toJson() => {
        'demoMode': demoMode,
        'plan': plan.name,
        'bizPlan': bizPlan.name,
        'creditConsent': creditConsent,
        'driverOnline': driverOnline,
        'farmEarned': farmEarned,
        'driverEarned': driverEarned,
        'saved': saved,
        'joined': joined.toList(),
        'driverKyc': driverKyc.toList(),
        'farmKyc': farmKyc.toList(),
        'rerouted': rerouted.toList(),
        'quotes': quotes.toList(),
        'paid': paid.toList(),
        'pins': pins,
        'stockApplied': stockApplied.toList(),
        'profile': profile.toJson(),
        'business': business.toJson(),
        'cart': cart,
        'ledger': [for (final e in ledger.take(200)) ledgerToJson(e)],
        'demoOrders': demoOrders,
      };

  factory PrivateState.fromJson(Map<String, dynamic> m) {
    Set<String> set(String k) => {for (final x in (m[k] as List? ?? const [])) x as String};
    return PrivateState(
      demoMode: m['demoMode'] as bool? ?? true,
      plan: _enum(Plan.values, m['plan'], Plan.starter),
      bizPlan: _enum(BizPlan.values, m['bizPlan'], BizPlan.command),
      creditConsent: m['creditConsent'] as bool? ?? true,
      driverOnline: m['driverOnline'] as bool? ?? false,
      farmEarned: (m['farmEarned'] as num?)?.toDouble() ?? 0,
      driverEarned: (m['driverEarned'] as num?)?.toDouble() ?? 0,
      saved: (m['saved'] as num?)?.toDouble() ?? 0,
      joined: set('joined'),
      driverKyc: set('driverKyc'),
      farmKyc: set('farmKyc'),
      rerouted: set('rerouted'),
      quotes: set('quotes'),
      paid: set('paid'),
      stockApplied: set('stockApplied'),
      profile: m['profile'] == null
          ? const ProfileSettings()
          : ProfileSettings.fromJson(Map<String, dynamic>.from(m['profile'] as Map)),
      business: m['business'] == null
          ? const BusinessProfile()
          : BusinessProfile.fromJson(Map<String, dynamic>.from(m['business'] as Map)),
      pins: {
        for (final e in (m['pins'] as Map? ?? const {}).entries)
          e.key as String: e.value as String
      },
      cart: {
        for (final e in (m['cart'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num).toInt()
      },
      ledger: [
        for (final e in (m['ledger'] as List? ?? const []))
          ledgerFromJson(Map<String, dynamic>.from(e as Map))
      ],
      demoOrders: [
        for (final e in (m['demoOrders'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map)
      ],
    );
  }
}
