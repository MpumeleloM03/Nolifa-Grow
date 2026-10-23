import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_boot.dart';
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
  Stream<List<WarehouseCert>> watchCerts();
  Future<void> putCert(WarehouseCert c);
}

class LocalWarehouseRepository implements WarehouseRepository {
  LocalWarehouseRepository({KeyValue? kv}) : _kv = kv ?? PrefsKv();
  LocalWarehouseRepository.memory() : this(kv: MemoryKv());

  static const _lotsKey = 'warehouse_lots_v1';
  static const _tempKey = 'warehouse_temps_v1';
  static const _certKey = 'warehouse_certs_v1';
  final KeyValue _kv;
  final _lots = StreamController<List<StockLot>>.broadcast();
  final _temps = StreamController<List<TempReading>>.broadcast();
  final _certs = StreamController<List<WarehouseCert>>.broadcast();
  List<WarehouseCert>? _c;
  List<StockLot>? _l;
  List<TempReading>? _t;
  Future<void>? _loading;

  @override
  bool get shared => false;

  Future<void> _ensure() => _loading ??= _load();

  Future<void> _load() async {
    _l = [];
    _t = [];
    _c = [];
    try {
      final a = await _kv.read(_lotsKey);
      if (a != null) _l = [for (final m in jsonDecode(a) as List) StockLot.fromJson(Map<String, dynamic>.from(m as Map))];
      final b = await _kv.read(_tempKey);
      if (b != null) _t = [for (final m in jsonDecode(b) as List) TempReading.fromJson(Map<String, dynamic>.from(m as Map))];
      final c = await _kv.read(_certKey);
      if (c != null) _c = [for (final m in jsonDecode(c) as List) WarehouseCert.fromJson(Map<String, dynamic>.from(m as Map))];
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
  Stream<List<WarehouseCert>> watchCerts() => _watch(_certs, () => _c!);

  @override
  Future<void> putCert(WarehouseCert c) async {
    await _ensure();
    _c = [c, for (final x in _c!) if (x.id != c.id) x];
    _certs.add(List.of(_c!));
    await _kv.write(_certKey, jsonEncode([for (final x in _c!) x.toJson()]));
  }

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

/// Shared records in `warehouse_lots`, `warehouse_readings` and `warehouse_certs`.
class SupabaseWarehouseRepository implements WarehouseRepository {
  SupabaseWarehouseRepository({SupabaseClient? db}) : _db = db ?? SupabaseBoot.client;
  final SupabaseClient _db;

  Map<String, dynamic> _doc(Map<String, dynamic> r) =>
      {...Map<String, dynamic>.from(r['data'] as Map), 'id': r['id']};

  @override
  bool get shared => true;

  @override
  Stream<List<StockLot>> watchLots() =>
      liveTable(_db, 'warehouse_lots').map((rows) => [for (final r in rows) StockLot.fromJson(_doc(r))]);

  @override
  Stream<List<TempReading>> watchReadings() => liveTable(_db, 'warehouse_readings').map((rows) {
        final list = [for (final r in rows) TempReading.fromJson(Map<String, dynamic>.from(r['data'] as Map))]
          ..sort((a, b) => b.at.compareTo(a.at));
        return list.take(200).toList();
      });

  @override
  Stream<List<WarehouseCert>> watchCerts() =>
      liveTable(_db, 'warehouse_certs').map((rows) => [for (final r in rows) WarehouseCert.fromJson(_doc(r))]);

  @override
  Future<void> putCert(WarehouseCert c) => _db.from('warehouse_certs').upsert({'id': c.id, 'data': c.toJson()});

  @override
  Future<void> putLot(StockLot lot) =>
      _db.rpc('save_lot', params: {'p_id': lot.id, 'p_data': lot.toJson()});

  @override
  Future<void> putReading(TempReading r) => _db.from('warehouse_readings').upsert({
        'id': '${r.hub}-${r.zone.name}-${r.at.millisecondsSinceEpoch}',
        'at': r.at.millisecondsSinceEpoch,
        'data': r.toJson(),
      });
}
