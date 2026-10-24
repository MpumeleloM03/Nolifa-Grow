import 'dart:async';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw failure into a sentence a farmer or driver can act on. Nothing
/// that reaches a screen should ever be an exception's own text.
String friendlyError(Object? e, {String doing = 'do that'}) {
  if (e is TimeoutException) return 'That took too long. Check your signal and try again.';
  if (e is SocketException) return 'No internet. Check your signal and try again.';
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) return 'Email or password is not right.';
    if (m.contains('jwt') || m.contains('expired') || m.contains('session')) {
      return 'Your sign-in ran out. Sign in again.';
    }
    return 'We could not sign you in. Try again.';
  }
  if (e is PostgrestException) {
    if (e.code == '42501') return 'Your account is not allowed to $doing yet.';
    if (e.code == '23505') return 'That already exists.';
    if (e.code == 'PGRST301' || (e.message.toLowerCase().contains('jwt'))) {
      return 'Your sign-in ran out. Sign in again.';
    }
    return 'The server could not $doing. Try again in a moment.';
  }
  final t = '$e'.toLowerCase();
  if (t.contains('socket') || t.contains('network') || t.contains('connection') || t.contains('failed host lookup') || t.contains('clientexception')) {
    return 'No internet. Check your signal and try again.';
  }
  if (t.contains('timeout')) return 'That took too long. Check your signal and try again.';
  return 'Something went wrong. Try again in a moment.';
}

/// A live list that heals itself. If the live channel drops or errors, the
/// last good list stays on screen, the list is re-read once, and the channel is
/// opened again after a growing pause. Callers only see an error if there has
/// never been any data at all.
Stream<List<Map<String, dynamic>>> resilientRows({
  required Stream<List<Map<String, dynamic>>> Function() open,
  required Future<List<Map<String, dynamic>>> Function() fetch,
}) {
  late final StreamController<List<Map<String, dynamic>>> out;
  StreamSubscription<List<Map<String, dynamic>>>? sub;
  Timer? retry;
  var delay = const Duration(seconds: 3);
  var hasData = false;
  var closed = false;

  void emit(List<Map<String, dynamic>> rows) {
    if (closed) return;
    hasData = true;
    out.add(rows);
  }

  void connect() {
    if (closed) return;
    sub?.cancel();
    sub = open().listen((rows) {
      delay = const Duration(seconds: 3);
      emit(rows);
    }, onError: (Object e) async {
      debugPrint('live list: $e');
      try {
        emit(await fetch().timeout(const Duration(seconds: 15)));
      } catch (e2) {
        if (!hasData && !closed) out.addError(e2);
      }
      retry?.cancel();
      retry = Timer(delay, connect);
      delay = Duration(seconds: (delay.inSeconds * 2).clamp(3, 60));
    }, cancelOnError: true);
  }

  out = StreamController<List<Map<String, dynamic>>>(
    onListen: connect,
    onCancel: () {
      closed = true;
      retry?.cancel();
      return sub?.cancel();
    },
  );
  return out.stream;
}
