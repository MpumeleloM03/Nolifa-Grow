import 'dart:async';
import 'dart:convert';
import '../security/secure_box.dart';
import 'market_codec.dart';
import 'market_models.dart';

/// Where Nolifa Drop keeps its data.
///
/// The app talks to this interface only. On a phone with no Firebase project
/// it uses [LocalMarketRepository] (saved on the device); once Firebase is
/// configured it switches to the Firestore implementation and orders, listings
/// and outbreak cases are shared between phones in real time.
abstract class MarketRepository {
  /// True when data is shared across devices.
  bool get shared;

  Future<PrivateState?> loadPrivate(String uid);
  Future<void> savePrivate(String uid, PrivateState s);

  Stream<List<Product>> watchProducts(String uid);
  Future<void> putProduct(Product p, String uid);

  /// My orders (as buyer, farmer or driver) plus open delivery jobs.
  Stream<List<Order>> watchOrders(String uid);
  Future<void> putOrder(Order o, String uid);

  /// Atomically assigns a driver to an open job. False if someone else got it.
  Future<bool> claimJob(String orderId, String uid, String name);

  /// Takes several jobs as one: every job is claimed, or none is.
  Future<bool> claimBatch(List<String> orderIds, String uid, String name);

  Stream<List<ReportCase>> watchCases(String uid);
  Future<void> putCase(ReportCase c, String uid);

  /// Adds one neighbour's confirmation. Each user can confirm a case once.
  Future<void> confirmCase(String caseId, String uid);
}

// ------------------------------------------------------------ key-value

abstract class KeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Phone storage for the market and water data. Sealed with AES-256-GCM, because
/// it holds orders, documents and health details.
class PrefsKv implements KeyValue {
  @override
  Future<String?> read(String key) => SecurePrefs.getString(key);

  @override
  Future<void> write(String key, String value) => SecurePrefs.setString(key, value);
}

class MemoryKv implements KeyValue {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}

// ---------------------------------------------------------------- local

/// Saves everything on this device. Behaves like the shared backend for one
/// user, so the rest of the app does not care which one is live.
class LocalMarketRepository implements MarketRepository {
  LocalMarketRepository([KeyValue? kv]) : _kv = kv ?? PrefsKv();

  /// In-memory only. Used by tests.
  LocalMarketRepository.memory() : _kv = MemoryKv();

  final KeyValue _kv;
  final _changed = StreamController<void>.broadcast();
  List<Map<String, dynamic>>? _products;
  List<Map<String, dynamic>>? _orders;
  List<Map<String, dynamic>>? _cases;

  @override
  bool get shared => false;

  Future<List<Map<String, dynamic>>> _list(String key) async {
    final raw = await _kv.read(key);
    if (raw == null) return [];
    return [
      for (final e in (jsonDecode(raw) as List)) Map<String, dynamic>.from(e as Map)
    ];
  }

  Future<void> _ensure() async {
    _products ??= await _list('mkt_products');
    _orders ??= await _list('mkt_orders');
    _cases ??= await _list('mkt_cases');
  }

  Future<void> _flush(String key, List<Map<String, dynamic>> v) async {
    await _kv.write(key, jsonEncode(v));
    _changed.add(null);
  }

  @override
  Future<PrivateState?> loadPrivate(String uid) async {
    final raw = await _kv.read('mkt_private_$uid');
    if (raw == null) return null;
    return PrivateState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> savePrivate(String uid, PrivateState s) =>
      _kv.write('mkt_private_$uid', jsonEncode(s.toJson()));

  Stream<T> _watch<T>(T Function() read) async* {
    await _ensure();
    yield read();
    yield* _changed.stream.map((_) => read());
  }

  @override
  Stream<List<Product>> watchProducts(String uid) => _watch(
      () => [for (final m in _products!) productFromJson(m, uid)]);

  @override
  Future<void> putProduct(Product p, String uid) async {
    await _ensure();
    _products!
      ..removeWhere((m) => m['id'] == p.id)
      ..insert(0, productToJson(p));
    await _flush('mkt_products', _products!);
  }

  @override
  Stream<List<Order>> watchOrders(String uid) => _watch(() => [
        for (final m in _orders!)
          if ((m['participants'] as List).contains(uid) ||
              (m['status'] == 'findingDriver' && m['driverId'] == null))
            orderFromJson(m, uid)
      ]);

  @override
  Future<void> putOrder(Order o, String uid) async {
    await _ensure();
    final json = orderToJson(o, uid);
    final i = _orders!.indexWhere((m) => m['id'] == o.id);
    if (i >= 0) {
      // Never let an older copy overwrite a newer one.
      if (((_orders![i]['rev'] as num?) ?? 0) >= o.rev) return;
      _orders![i] = json;
    } else {
      _orders!.insert(0, json);
    }
    await _flush('mkt_orders', _orders!);
  }

  @override
  Future<bool> claimJob(String orderId, String uid, String name) async {
    await _ensure();
    final i = _orders!.indexWhere((m) => m['id'] == orderId);
    if (i < 0) return false;
    final m = _orders![i];
    if (m['driverId'] != null || m['status'] != 'findingDriver') return false;
    m['driverId'] = uid;
    m['driver'] = name;
    m['status'] = 'assigned';
    m['rev'] = ((m['rev'] as num?) ?? 0).toInt() + 1;
    m['participants'] = [...(m['participants'] as List), uid];
    await _flush('mkt_orders', _orders!);
    return true;
  }

  @override
  Future<bool> claimBatch(List<String> orderIds, String uid, String name) async {
    await _ensure();
    bool open(String id) {
      final m = _orders!.where((x) => x['id'] == id).firstOrNull;
      return m != null && m['driverId'] == null && m['status'] == 'findingDriver';
    }

    if (!orderIds.every(open)) return false;
    for (final id in orderIds) {
      await claimJob(id, uid, name);
    }
    return true;
  }

  @override
  Stream<List<ReportCase>> watchCases(String uid) =>
      _watch(() => [for (final m in _cases!) caseFromJson(m, uid)]);

  @override
  Future<void> putCase(ReportCase c, String uid) async {
    await _ensure();
    final json = caseToJson(c, uid);
    final i = _cases!.indexWhere((m) => m['id'] == c.id);
    i >= 0 ? _cases![i] = json : _cases!.insert(0, json);
    await _flush('mkt_cases', _cases!);
  }

  @override
  Future<void> confirmCase(String caseId, String uid) async {
    await _ensure();
    final i = _cases!.indexWhere((m) => m['id'] == caseId);
    if (i < 0) return;
    final by = [...(_cases![i]['confirmedBy'] as List? ?? const [])];
    if (by.contains(uid)) return;
    by.add(uid);
    _cases![i]['confirmedBy'] = by;
    _cases![i]['confirmations'] = ((_cases![i]['confirmations'] as num?) ?? 0).toInt() + 1;
    if (_cases![i]['confirmations'] >= 2 && _cases![i]['stage'] == 'aiChecked') {
      _cases![i]['stage'] = 'corroborated';
    }
    await _flush('mkt_cases', _cases!);
  }
}
