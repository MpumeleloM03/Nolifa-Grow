import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../delivery/delivery_plan.dart' show hubs;
import '../delivery/hub_desk.dart' show canRunHubProvider;
import '../market/market_models.dart' show Category;
import '../market/market_store.dart';
import 'warehouse_models.dart';
import 'warehouse_repository.dart';

/// The pretend farm that owns the demo stock.
const demoFarmerId = 'demo-fatboy';

const _demoLots = <(String, double, StorageZone, int)>[
  ('Beef mince', 40, StorageZone.chilled, 4),
  ('Chicken breast', 30, StorageZone.chilled, 3),
  ('Beef stew', 25, StorageZone.chilled, 5),
  ('Beef sausage', 20, StorageZone.chilled, 6),
  ('Brisket', 18, StorageZone.frozen, 90),
  ('Chicken thighs', 24, StorageZone.frozen, 120),
];

final warehouseRepositoryProvider = Provider<WarehouseRepository>((ref) => LocalWarehouseRepository());
final warehouseClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class WarehouseState {
  final List<StockLot> lots;
  final List<TempReading> readings; // newest first
  final bool shared;
  const WarehouseState({this.lots = const [], this.readings = const [], this.shared = false});

  /// Lots a farm can see: its own. Staff see all.
  List<StockLot> forFarmer(String uid) => [for (final l in lots) if (l.farmerId == uid) l];

  List<StockLot> get stored => [for (final l in lots) if (l.inStock) l];
  List<StockLot> get expected => [for (final l in lots) if (l.status == LotStatus.expected) l];

  /// The newest reading for a room, or null.
  TempReading? latest(String hub, StorageZone z) {
    for (final r in readings) {
      if (r.hub == hub && r.zone == z) return r;
    }
    return null;
  }

  /// A room is in trouble when its newest reading is outside its band.
  bool zoneAtRisk(String hub, StorageZone z) {
    final r = latest(hub, z);
    return r != null && !r.ok;
  }

  /// How much of a product a farm has in storage, ready to send.
  double available(String farmName, String productName) => stored
      .where((l) => _same(l.farmName, farmName) && _same(l.productName, productName))
      .fold(0.0, (a, l) => a + l.remaining);
}

bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

class WarehouseStore extends Notifier<WarehouseState> {
  StreamSubscription<List<StockLot>>? _a;
  StreamSubscription<List<TempReading>>? _b;
  int _seq = 0;

  WarehouseRepository get _repo => ref.read(warehouseRepositoryProvider);
  DateTime get _now => ref.read(warehouseClockProvider)();
  String get _uid => ref.read(marketUidProvider);

  @override
  WarehouseState build() {
    final repo = ref.watch(warehouseRepositoryProvider);
    _a = repo.watchLots().listen((l) => state = WarehouseState(lots: l, readings: state.readings, shared: repo.shared));
    _b = repo.watchReadings().listen((r) => state =
        WarehouseState(lots: state.lots, readings: [...r]..sort((x, y) => y.at.compareTo(x.at)), shared: repo.shared));
    ref.onDispose(() {
      _a?.cancel();
      _b?.cancel();
    });
    return WarehouseState(shared: repo.shared);
  }

  bool get _staff => ref.read(canRunHubProvider);

  /// A farm tells the warehouse what it is bringing.
  Future<StockLot?> announce({
    required String productName,
    required Category category,
    required String unit,
    required double qty,
    required StorageZone zone,
    required DateTime useBy,
    required DateTime expectedAt,
    String hub = 'Durban hub',
  }) async {
    if (qty <= 0 || !StorageZone.allowedFor(category).contains(zone)) return null;
    if (!useBy.isAfter(_now)) return null;
    final farm = ref.read(marketProvider).profile.farmName;
    final now = _now;
    final lot = StockLot(
      id: 'dep-${now.microsecondsSinceEpoch}-${_seq++}-$_uid',
      hub: hub,
      farmerId: _uid,
      farmName: farm.trim().isEmpty ? ref.read(marketNameProvider) : farm.trim(),
      productName: productName.trim(),
      category: category,
      unit: unit,
      qty: qty,
      remaining: 0,
      zone: zone,
      useBy: useBy,
      expectedAt: expectedAt,
      status: LotStatus.expected,
      events: [LotEvent(now, 'Deposit announced: ${_fmt(qty)} $unit, ${zone.label}')],
    );
    await _repo.putLot(lot);
    return lot;
  }

  /// Staff check a delivery in. It is accepted only if the goods arrived inside
  /// the room's temperature band. Returns null when accepted, otherwise why not.
  Future<String?> receive(String lotId, {required double qty, required double tempC, String? note}) async {
    if (!_staff) return 'Only warehouse staff can check goods in.';
    final lot = _find(lotId);
    if (lot == null || lot.status != LotStatus.expected) return 'This deposit is not waiting to be checked in.';
    if (qty <= 0) return 'Enter the quantity that arrived.';
    final now = _now;
    if (!lot.zone.ok(tempC)) {
      final why = 'Arrived at ${tempC.toStringAsFixed(1)} C. ${lot.zone.label} goods must be ${lot.zone.band}.';
      await _repo.putLot(lot.copyWith(
          status: LotStatus.rejected,
          receivedAt: now,
          receivedTempC: tempC,
          note: why,
          events: [...lot.events, LotEvent(now, 'Rejected at the door. $why')]));
      return why;
    }
    final hubId = (hubs.where((h) => h.name == lot.hub).firstOrNull ?? hubs.first).id.toUpperCase();
    final tagged = state.lots.where((l) => l.tag != null && l.hub == lot.hub).length + 1;
    final inZone = state.lots.where((l) => l.bay != null && l.hub == lot.hub && l.zone == lot.zone).length;
    final tag = 'NLF-$hubId-${tagged.toString().padLeft(4, '0')}';
    final bay = '${lot.zone.code}${inZone ~/ 12 + 1}-${(inZone % 12 + 1).toString().padLeft(2, '0')}';
    await _repo.putLot(lot.copyWith(
      status: LotStatus.stored,
      qty: qty,
      remaining: qty,
      tag: tag,
      bay: bay,
      receivedAt: now,
      receivedTempC: tempC,
      note: note ?? '',
      events: [
        ...lot.events,
        LotEvent(now, 'Checked in: ${_fmt(qty)} ${lot.unit} at ${tempC.toStringAsFixed(1)} C. Tag $tag, bay $bay'),
      ],
    ));
    return null;
  }

  Future<bool> reject(String lotId, String reason) async {
    if (!_staff) return false;
    final lot = _find(lotId);
    if (lot == null || lot.status != LotStatus.expected) return false;
    final now = _now;
    await _repo.putLot(lot.copyWith(
        status: LotStatus.rejected, note: reason, events: [...lot.events, LotEvent(now, 'Rejected: $reason')]));
    return true;
  }

  /// Takes [qty] of a farm's product out of storage for an order, using the
  /// goods that expire first. Returns what was taken, or null if there is not
  /// enough (then nothing is touched).
  Future<List<Pick>?> dispatch(String farmName, String productName, double qty, String orderId) async {
    if (!_staff || qty <= 0) return null;
    final candidates = state.stored
        .where((l) => _same(l.farmName, farmName) && _same(l.productName, productName) && l.zone.ok(_lastKnown(l)))
        .toList()
      ..sort((a, b) => a.useBy.compareTo(b.useBy));
    if (candidates.fold(0.0, (a, l) => a + l.remaining) < qty) return null;
    var need = qty;
    final picks = <Pick>[];
    final now = _now;
    for (final l in candidates) {
      if (need <= 0) break;
      final take = math.min(need, l.remaining);
      need -= take;
      final left = l.remaining - take;
      picks.add(Pick(l.id, l.tag ?? l.id, take));
      await _repo.putLot(l.copyWith(
        remaining: left,
        status: left <= 0 ? LotStatus.emptied : LotStatus.stored,
        events: [...l.events, LotEvent(now, 'Picked ${_fmt(take)} ${l.unit} for order $orderId')],
      ));
    }
    return picks;
  }

  // A lot whose room is currently out of range is not sent out until staff
  // have dealt with it; use the room's newest reading to decide.
  double _lastKnown(StockLot l) {
    final r = state.latest(l.hub, l.zone);
    return r?.c ?? (l.zone.minC + l.zone.maxC) / 2;
  }

  /// Writes off lots that passed their use-by date. Returns how many.
  Future<int> writeOffExpired() async {
    final now = _now;
    var n = 0;
    for (final l in state.stored.where((l) => l.daysLeft(now) < 0)) {
      n++;
      await _repo.putLot(l.copyWith(
          status: LotStatus.expired, events: [...l.events, LotEvent(now, 'Past use-by. Written off, ${_fmt(l.remaining)} ${l.unit} removed')]));
    }
    return n;
  }

  Future<void> logTemp(String hub, StorageZone zone, double c, {bool manual = true}) =>
      _repo.putReading(TempReading(hub, zone, c, _now, manual: manual));

  /// Demo only: the rooms report a reading from their pretend sensors. Each
  /// room sits near the middle of its band with a small wobble.
  Future<void> simulateSensors({String hub = 'Durban hub'}) async {
    final t = _now.millisecondsSinceEpoch / 60000;
    for (final z in StorageZone.values) {
      final mid = (z.minC + z.maxC) / 2;
      final span = (z.maxC - z.minC) / 2;
      final c = mid + span * 0.35 * math.sin(t / 7 + z.index);
      await _repo.putReading(TempReading(hub, z, double.parse(c.toStringAsFixed(1)), _now));
    }
  }

  /// Demo only: puts stock from the demo butchery in the warehouse so a
  /// judge can see goods already stored, tagged and cold. It is marked as demo
  /// stock and belongs to no real farm.
  Future<void> seedDemoIfEmpty() async {
    if (state.lots.any((l) => l.farmerId == demoFarmerId)) return;
    final now = _now;
    var n = 0;
    for (final d in _demoLots) {
      n++;
      final tag = 'NLF-DBN-${(900 + n).toString().padLeft(4, '0')}';
      await _repo.putLot(StockLot(
        id: 'demo-lot-$n',
        hub: 'Durban hub',
        farmerId: demoFarmerId,
        farmName: 'Fatboy Butcheries',
        productName: d.$1,
        category: Category.meat,
        unit: 'kg',
        qty: d.$2,
        remaining: d.$2,
        zone: d.$3,
        useBy: now.add(Duration(days: d.$4)),
        expectedAt: now.subtract(const Duration(days: 1)),
        status: LotStatus.stored,
        tag: tag,
        bay: '${d.$3.code}1-${n.toString().padLeft(2, '0')}',
        receivedAt: now.subtract(const Duration(hours: 20)),
        receivedTempC: d.$3 == StorageZone.frozen ? -19.0 : 2.5,
        note: 'Demo stock',
        events: [
          LotEvent(now.subtract(const Duration(hours: 20)),
              'Checked in: ${d.$2.round()} kg at ${d.$3 == StorageZone.frozen ? '-19.0' : '2.5'} C. Tag $tag (demo stock)')
        ],
      ));
    }
  }

  StockLot? _find(String id) {
    for (final l in state.lots) {
      if (l.id == id) return l;
    }
    return null;
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

final warehouseProvider = NotifierProvider<WarehouseStore, WarehouseState>(WarehouseStore.new);
