import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_cache.dart';
import 'supabase_boot.dart';

/// One change made while there was no signal, waiting to be sent.
class PendingWrite {
  final String id;
  final String op; // 'rpc', 'insert' or 'upsert'
  final String target; // function or table name
  final String? schema;
  final Map<String, dynamic> body;
  final String label;
  final DateTime at;
  const PendingWrite(this.id, this.op, this.target, this.schema, this.body, this.label, this.at);

  Map<String, dynamic> toJson() => {
        'id': id,
        'op': op,
        'target': target,
        'schema': schema,
        'body': body,
        'label': label,
        'at': at.millisecondsSinceEpoch,
      };

  factory PendingWrite.fromJson(Map<String, dynamic> m) => PendingWrite(
        m['id'] as String,
        m['op'] as String,
        m['target'] as String,
        m['schema'] as String?,
        Map<String, dynamic>.from(m['body'] as Map),
        m['label'] as String? ?? '',
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
      );
}

bool isNetworkError(Object e) {
  if (e is SocketException || e is TimeoutException) return true;
  final t = '$e'.toLowerCase();
  return t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('clientexception') ||
      t.contains('network is unreachable') ||
      t.contains('connection refused') ||
      t.contains('connection closed') ||
      t.contains('connection reset') ||
      t.contains('timed out') ||
      t.contains('authretryablefetch');
}

/// Changes that matter to the problem the apps solve (a water request, an
/// outbreak report, a stock count) must not be lost because the signal dropped.
/// They are tried now; if there is no network they wait on the phone and go
/// out, in order, the moment the phone is back online. Money and delivery
/// steps are not queued: those must be checked by the server as they happen.
///
/// A change the server refuses (a rule, a permission) is dropped, not retried.
class OfflineOutbox extends ValueNotifier<int> {
  OfflineOutbox() : super(0);
  static final instance = OfflineOutbox();

  /// Sends one change. Tests replace it.
  Future<void> Function(PendingWrite w, SupabaseClient? db) sender = _sendToSupabase;

  /// Who is signed in; the queue belongs to them. Tests replace it.
  String? Function() currentUser = () => SupabaseBoot.ready ? SupabaseBoot.client.auth.currentUser?.id : null;

  final List<PendingWrite> _queue = [];
  bool _loaded = false;
  bool _flushing = false;
  Timer? _timer;
  String? _loadedFor;

  List<PendingWrite> get pending => List.unmodifiable(_queue);

  static Future<void> _sendToSupabase(PendingWrite w, SupabaseClient? client) async {
    final db = client ?? SupabaseBoot.client;
    switch (w.op) {
      case 'rpc':
        if (w.schema == null) {
          await db.rpc(w.target, params: w.body);
        } else {
          await db.schema(w.schema!).rpc(w.target, params: w.body);
        }
      case 'insert':
        await db.from(w.target).insert(w.body);
      case 'upsert':
        await db.from(w.target).upsert(w.body);
    }
  }

  /// Starts watching for the network to come back. Call once at start-up.
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => flush());
    SyncStatus.instance.addListener(_onSync);
    flush();
  }

  bool _wasOffline = false;
  void _onSync() {
    final off = SyncStatus.instance.value.offline;
    if (_wasOffline && !off) flush();
    _wasOffline = off;
  }

  String get _key => 'outbox:v1:${currentUser() ?? 'none'}';

  Future<void> _load() async {
    final who = currentUser();
    if (_loaded && _loadedFor == who) return;
    _queue.clear();
    _loaded = true;
    _loadedFor = who;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        _queue.addAll([for (final m in jsonDecode(raw) as List) PendingWrite.fromJson(Map<String, dynamic>.from(m as Map))]);
      }
    } catch (e) {
      debugPrint('outbox: could not read the saved queue: $e');
    }
    value = _queue.length;
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await p.remove(_key);
      } else {
        await p.setString(_key, jsonEncode([for (final w in _queue) w.toJson()]));
      }
    } catch (e) {
      debugPrint('outbox: could not save the queue: $e');
    }
    value = _queue.length;
  }

  /// Sends a change now. Returns true when the server took it, false when it was
  /// kept to send later. A server refusal is thrown, so the screen can say why.
  Future<bool> send({required String label, required String op, required String target, required Map<String, dynamic> body, String? schema, SupabaseClient? client}) async {
    await _load();
    final w = PendingWrite('${DateTime.now().microsecondsSinceEpoch}', op, target, schema, body, label, DateTime.now());
    // Keep order: if older changes are waiting, this one waits behind them.
    if (_queue.isEmpty) {
      try {
        await sender(w, client);
        return true;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
      }
    }
    _queue.add(w);
    await _save();
    return false;
  }

  Future<bool> rpc(String label, String fn, Map<String, dynamic> params, {String? schema, SupabaseClient? client}) =>
      send(label: label, op: 'rpc', target: fn, body: params, schema: schema, client: client);

  Future<bool> insert(String label, String table, Map<String, dynamic> row, {SupabaseClient? client}) =>
      send(label: label, op: 'insert', target: table, body: row, client: client);

  Future<bool> upsert(String label, String table, Map<String, dynamic> row, {SupabaseClient? client}) =>
      send(label: label, op: 'upsert', target: table, body: row, client: client);

  /// Sends what is waiting, oldest first. Stops at the first network failure.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      await _load();
      while (_queue.isNotEmpty) {
        final w = _queue.first;
        try {
          await sender(w, null);
          sent++;
        } catch (e) {
          if (isNetworkError(e)) break;
          // The server said no. Retrying will not change that.
          debugPrint('outbox: dropped "${w.label}": $e');
          if (e is PostgrestException) {/* refused by a rule */}
        }
        _queue.removeAt(0);
        await _save();
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  @visibleForTesting
  void resetForTest() {
    _queue.clear();
    _loaded = false;
    _loadedFor = null;
    _wasOffline = false;
    value = 0;
  }
}
