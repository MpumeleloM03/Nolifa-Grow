import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../market/market_repository.dart' show KeyValue, MemoryKv, PrefsKv;
import 'warehouse_models.dart';

/// Where warehouse records live. Local keeps them on this phone; Firestore
/// shares them between the farmer's phone and the warehouse desk.
abstract class WarehouseRepository {
  bool get shared;
  Stream<List<StockLot>> watchLots();
  Stream<List<TempReading>> watchReadings();
  Future<void> putLot(StockLot lot);
  Future<void> putReading(TempReading r);
}

class LocalWarehouseRepository implements WarehouseRepository {
  LocalWarehouseRepository({KeyValue? kv}) : _kv = kv ?? PrefsKv();
  LocalWarehouseRepository.memory() : this(kv: MemoryKv());

  static const _lotsKey = 'warehouse_lots_v1';
  static const _tempKey = 'warehouse_temps_v1';
  final KeyValue _kv;
  final _lots = StreamController<List<StockLot>>.broadcast();
  final _temps = StreamController<List<TempReading>>.broadcast();
  List<StockLot>? _l;
  List<TempReading>? _t;
  Future<void>? _loading;

  @override
  bool get shared => false;

  Future<void> _ensure() => _loading ??= _load();

  Future<void> _load() async {
    _l = [];
    _t = [];
    try {
      final a = await _kv.read(_lotsKey);
      if (a != null) _l = [for (final m in jsonDecode(a) as List) StockLot.fromJson(Map<String, dynamic>.from(m as Map))];
      final b = await _kv.read(_tempKey);
      if (b != null) _t = [for (final m in jsonDecode(b) as List) TempReading.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      // Unreadable records start again rather than crash.
    }
  }

  Stream<List<T>> _watch<T>(StreamController<List<T>> ctl, List<T> Function() current) {
    late final StreamController<List<T>> out;
    StreamSubscription<List<T>>? sub;
    out = StreamController<List<T>>(
      onListen: () async {
        sub = ctl.stream.listen(out.add);
        await _ensure();
        if (!out.isClosed) out.add(List.of(current()));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Stream<List<StockLot>> watchLots() => _watch(_lots, () => _l!);

  @override
  Stream<List<TempReading>> watchReadings() => _watch(_temps, () => _t!);

  @override
  Future<void> putLot(StockLot lot) async {
    await _ensure();
    _l = [lot, for (final x in _l!) if (x.id != lot.id) x];
    _lots.add(List.of(_l!));
    await _kv.write(_lotsKey, jsonEncode([for (final x in _l!) x.toJson()]));
  }

  @override
  Future<void> putReading(TempReading r) async {
    await _ensure();
    _t = [r, ..._t!].take(400).toList();
    _temps.add(List.of(_t!));
    await _kv.write(_tempKey, jsonEncode([for (final x in _t!) x.toJson()]));
  }
}

/// Shared records in `warehouseLots/{id}` and `warehouseReadings/{id}`.
class FirestoreWarehouseRepository implements WarehouseRepository {
  FirestoreWarehouseRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  bool get shared => true;

  @override
  Stream<List<StockLot>> watchLots() => _db
      .collection('warehouseLots')
      .snapshots()
      .map((q) => [for (final d in q.docs) StockLot.fromJson({...d.data(), 'id': d.id})]);

  @override
  Stream<List<TempReading>> watchReadings() => _db
      .collection('warehouseReadings')
      .orderBy('at', descending: true)
      .limit(200)
      .snapshots()
      .map((q) => [for (final d in q.docs) TempReading.fromJson(d.data())]);

  @override
  Future<void> putLot(StockLot lot) => _db.collection('warehouseLots').doc(lot.id).set(lot.toJson());

  @override
  Future<void> putReading(TempReading r) =>
      _db.collection('warehouseReadings').doc('${r.hub}-${r.zone.name}-${r.at.millisecondsSinceEpoch}').set(r.toJson());
}
