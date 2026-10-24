import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last good copy of each shared list, kept on the phone.
///
/// A farmer on a dirt road with no signal still needs the water zones, the
/// road alerts and their own orders. Every live list saves its latest rows
/// here and shows them first on the next start, before the network answers.
/// Copies belong to one signed-in person and are wiped on sign-out.
class OfflineCache {
  static const _prefix = 'offline:v1:';
  static const _maxBytes = 600 * 1024;
  static final _pending = <String, Timer>{};

  /// Saves [rows] a moment after the last change, so a busy realtime feed does
  /// not hammer storage.
  static void save(String key, List<Map<String, dynamic>> rows) {
    _pending[key]?.cancel();
    _pending[key] = Timer(const Duration(seconds: 2), () async {
      _pending.remove(key);
      try {
        final body = jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'rows': rows});
        if (body.length > _maxBytes) return; // too big to be worth keeping
        await (await SharedPreferences.getInstance()).setString('$_prefix$key', body);
      } catch (e) {
        debugPrint('offline cache: could not save $key: $e');
      }
    });
  }

  static Future<({DateTime at, List<Map<String, dynamic>> rows})?> load(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString('$_prefix$key');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map;
      return (
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        rows: [for (final r in (m['rows'] as List)) Map<String, dynamic>.from(r as Map)],
      );
    } catch (e) {
      debugPrint('offline cache: could not read $key: $e');
      return null;
    }
  }

  /// Removes every saved copy. Called when the person signs out.
  static Future<void> clearAll() async {
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}

class SyncState {
  /// True when the phone has no signal, or live data stopped arriving.
  final bool offline;

  /// When live data last arrived, or the time of the saved copy being shown.
  final DateTime? asOf;
  const SyncState({this.offline = false, this.asOf});
}

/// What the phone knows about its own connection, from the lists that depend
/// on it. The offline pill at the top of every app reads this.
class SyncStatus extends ValueNotifier<SyncState> {
  SyncStatus() : super(const SyncState());

  static final instance = SyncStatus();

  bool _noSignal = false;
  bool _stale = false;
  DateTime? _asOf;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void _publish() => value = SyncState(offline: _noSignal || _stale, asOf: _asOf);

  /// Live data arrived.
  void live() {
    _stale = false;
    _asOf = DateTime.now();
    _publish();
  }

  /// A saved copy is being shown because live data could not be reached.
  void servedCache(DateTime at) {
    _stale = true;
    if (_asOf == null || at.isAfter(_asOf!)) _asOf = at;
    _publish();
  }

  /// The network did not answer and there is nothing newer than what is shown.
  void failed() {
    _stale = true;
    _publish();
  }

  /// Starts listening for the phone losing and regaining signal.
  void watchConnectivity() {
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      _noSignal = r.isEmpty || r.every((x) => x == ConnectivityResult.none);
      _publish();
    }, onError: (_) {});
    Connectivity().checkConnectivity().then((r) {
      _noSignal = r.isEmpty || r.every((x) => x == ConnectivityResult.none);
      _publish();
    }).catchError((_) {});
  }

  @visibleForTesting
  void reset() {
    _noSignal = false;
    _stale = false;
    _asOf = null;
    _publish();
  }
}
