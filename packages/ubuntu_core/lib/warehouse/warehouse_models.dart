import '../market/market_models.dart' show Category;

/// The rooms in a Nolifa warehouse. Each has a temperature band that goods in
/// it must stay inside. Meat and poultry go in chilled or frozen rooms.
enum StorageZone {
  frozen('Frozen room', 'F', -25.0, -15.0),
  chilled('Chilled room', 'C', 0.0, 4.0),
  cool('Cool room', 'K', 8.0, 12.0),
  ambient('Dry store', 'D', 10.0, 25.0);

  final String label;
  final String code; // first letter of the bay
  final double minC;
  final double maxC;
  const StorageZone(this.label, this.code, this.minC, this.maxC);

  String get band => '${minC.round()} to ${maxC.round()} C';

  /// A reading is acceptable inside the band, with 1 degree of slack for a
  /// door being opened.
  bool ok(double c) => c >= minC - 1 && c <= maxC + 1;

  static StorageZone parse(String? raw) =>
      StorageZone.values.firstWhere((z) => z.name == raw, orElse: () => StorageZone.chilled);

  /// Where a category goes by default. Meat can be frozen, so the farmer picks.
  static StorageZone defaultFor(Category c) => switch (c) {
        Category.meat => StorageZone.chilled,
        Category.dairy => StorageZone.chilled,
        Category.veg || Category.fruit => StorageZone.cool,
        Category.grain || Category.water || Category.essentials => StorageZone.ambient,
      };

  /// Which zones a category may be stored in.
  static List<StorageZone> allowedFor(Category c) => switch (c) {
        Category.meat => [StorageZone.chilled, StorageZone.frozen],
        Category.dairy => [StorageZone.chilled],
        Category.veg || Category.fruit => [StorageZone.cool, StorageZone.chilled],
        Category.grain || Category.water || Category.essentials => [StorageZone.ambient],
      };
}

enum LotStatus {
  expected('Expected'),
  stored('In storage'),
  rejected('Rejected'),
  emptied('All sent out'),
  expired('Written off');

  final String label;
  const LotStatus(this.label);

  static LotStatus parse(String? raw) =>
      LotStatus.values.firstWhere((s) => s.name == raw, orElse: () => LotStatus.expected);
}

class LotEvent {
  final DateTime at;
  final String text;
  const LotEvent(this.at, this.text);

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'text': text};

  factory LotEvent.fromJson(Map<String, dynamic> m) => LotEvent(
      DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()), m['text'] as String? ?? '');
}

/// One batch of one product that a farm deposits. It gets a tag when the
/// warehouse checks it in, and every movement is logged on it.
class StockLot {
  final String id;
  final String hub; // 'Durban hub'
  final String farmerId;
  final String farmName;
  final String productName;
  final Category category;
  final String unit;
  final double qty; // checked in
  final double remaining;
  final StorageZone zone;
  final DateTime useBy;
  final DateTime expectedAt;
  final LotStatus status;
  final String? tag; // set at check-in
  final String? bay; // set at check-in
  final DateTime? receivedAt;
  final double? receivedTempC;
  final String note;
  final List<LotEvent> events;

  const StockLot({
    required this.id,
    required this.hub,
    required this.farmerId,
    required this.farmName,
    required this.productName,
    required this.category,
    required this.unit,
    required this.qty,
    required this.remaining,
    required this.zone,
    required this.useBy,
    required this.expectedAt,
    required this.status,
    this.tag,
    this.bay,
    this.receivedAt,
    this.receivedTempC,
    this.note = '',
    this.events = const [],
  });

  bool get inStock => status == LotStatus.stored && remaining > 0;

  int daysLeft(DateTime now) =>
      DateTime(useBy.year, useBy.month, useBy.day).difference(DateTime(now.year, now.month, now.day)).inDays;

  StockLot copyWith({
    double? qty,
    double? remaining,
    LotStatus? status,
    String? tag,
    String? bay,
    DateTime? receivedAt,
    double? receivedTempC,
    String? note,
    List<LotEvent>? events,
  }) =>
      StockLot(
        id: id,
        hub: hub,
        farmerId: farmerId,
        farmName: farmName,
        productName: productName,
        category: category,
        unit: unit,
        qty: qty ?? this.qty,
        remaining: remaining ?? this.remaining,
        zone: zone,
        useBy: useBy,
        expectedAt: expectedAt,
        status: status ?? this.status,
        tag: tag ?? this.tag,
        bay: bay ?? this.bay,
        receivedAt: receivedAt ?? this.receivedAt,
        receivedTempC: receivedTempC ?? this.receivedTempC,
        note: note ?? this.note,
        events: events ?? this.events,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hub': hub,
        'farmerId': farmerId,
        'farmName': farmName,
        'product': productName,
        'category': category.name,
        'unit': unit,
        'qty': qty,
        'remaining': remaining,
        'zone': zone.name,
        'useBy': useBy.millisecondsSinceEpoch,
        'expectedAt': expectedAt.millisecondsSinceEpoch,
        'status': status.name,
        'tag': tag,
        'bay': bay,
        'receivedAt': receivedAt?.millisecondsSinceEpoch,
        'receivedTempC': receivedTempC,
        'note': note,
        'events': [for (final e in events) e.toJson()],
      };

  factory StockLot.fromJson(Map<String, dynamic> m) => StockLot(
        id: m['id'] as String,
        hub: m['hub'] as String? ?? 'Durban hub',
        farmerId: m['farmerId'] as String? ?? '',
        farmName: m['farmName'] as String? ?? 'Farm',
        productName: m['product'] as String? ?? '',
        category: Category.values.firstWhere((c) => c.name == m['category'], orElse: () => Category.veg),
        unit: m['unit'] as String? ?? 'kg',
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        remaining: (m['remaining'] as num?)?.toDouble() ?? 0,
        zone: StorageZone.parse(m['zone'] as String?),
        useBy: DateTime.fromMillisecondsSinceEpoch((m['useBy'] as num).toInt()),
        expectedAt: DateTime.fromMillisecondsSinceEpoch((m['expectedAt'] as num).toInt()),
        status: LotStatus.parse(m['status'] as String?),
        tag: m['tag'] as String?,
        bay: m['bay'] as String?,
        receivedAt: m['receivedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['receivedAt'] as num).toInt()),
        receivedTempC: (m['receivedTempC'] as num?)?.toDouble(),
        note: m['note'] as String? ?? '',
        events: [
          for (final e in (m['events'] as List? ?? const [])) LotEvent.fromJson(Map<String, dynamic>.from(e as Map))
        ],
      );
}

/// A temperature reading for one room.
class TempReading {
  final String hub;
  final StorageZone zone;
  final double c;
  final DateTime at;
  final bool manual; // typed in by staff; otherwise from a sensor
  const TempReading(this.hub, this.zone, this.c, this.at, {this.manual = false});

  bool get ok => zone.ok(c);

  Map<String, dynamic> toJson() =>
      {'hub': hub, 'zone': zone.name, 'c': c, 'at': at.millisecondsSinceEpoch, 'manual': manual};

  factory TempReading.fromJson(Map<String, dynamic> m) => TempReading(
        m['hub'] as String? ?? 'Durban hub',
        StorageZone.parse(m['zone'] as String?),
        (m['c'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        manual: m['manual'] as bool? ?? false,
      );
}

/// What was taken from which lot for an order.
class Pick {
  final String lotId;
  final String tag;
  final double qty;
  const Pick(this.lotId, this.tag, this.qty);
}
