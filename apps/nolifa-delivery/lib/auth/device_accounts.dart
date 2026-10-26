import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;

import 'auth_user.dart';

const _accountsKey = 'drop_accounts';
const _sessionKey = 'drop_session';

/// Hashing rounds. Slows down guessing if someone copies the phone's storage.
const _rounds = 4096;

/// Accounts kept on this phone, used when Supabase is not connected so the app
/// still works offline and in demos.
///
/// Only a salted SHA-256 hash of each password is stored, never the password.
/// These accounts never leave the device: they cannot be used on another phone.
class DeviceAccounts {
  final _changes = StreamController<AuthUser?>.broadcast();
  final _rng = Random.secure();

  Future<SharedPreferences> get _prefs async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      throw const AuthException(
        'This phone would not let the app save your account. Restart the app and try again.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    await _prefs; // fails with a clear message if storage is blocked
    final raw = await SecurePrefs.getString(_accountsKey);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          Map<String, dynamic>.from(e as Map),
      ];
    } catch (e) {
      // Unreadable is treated as empty so the person can still sign up again.
      debugPrint('auth: saved accounts could not be read: $e');
      return [];
    }
  }

  static AuthUser _user(Map<String, dynamic> m) => AuthUser(
    uid: m['uid'] as String,
    name: m['name'] as String,
    email: m['email'] as String,
  );

  static String _hash(String salt, String password) {
    List<int> digest = utf8.encode('$salt:$password');
    for (var i = 0; i < _rounds; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  String _random(int bytes) =>
      base64UrlEncode([for (var i = 0; i < bytes; i++) _rng.nextInt(256)]);

  /// The person signed in on this phone, if any.
  Future<AuthUser?> current() async {
    final prefs = await _prefs;
    final uid = prefs.getString(_sessionKey);
    if (uid == null) return null;
    for (final m in await _load()) {
      if (m['uid'] == uid) return _user(m);
    }
    return null;
  }

  /// Emits the signed-in person now and again on every sign-in or sign-out.
  Stream<AuthUser?> watchSession() async* {
    yield await current();
    yield* _changes.stream;
  }

  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final problem =
        checkName(name) ?? checkEmail(email) ?? checkPassword(password);
    if (problem != null) throw AuthException(problem);
    final key = email.trim().toLowerCase();
    final accounts = await _load();
    if (accounts.any((m) => m['email'] == key)) {
      throw const AuthException(
        'An account with that email already exists on this phone. Sign in instead.',
      );
    }
    final salt = _random(16);
    final account = {
      'uid': 'local-${_random(9)}',
      'name': name.trim(),
      'email': key,
      'salt': salt,
      'hash': _hash(salt, password),
    };
    final prefs = await _prefs;
    await SecurePrefs.setString(_accountsKey, jsonEncode([...accounts, account]));
    await prefs.setString(_sessionKey, account['uid']!);
    final user = _user(account);
    _changes.add(user);
    return user;
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    for (final m in await _load()) {
      if (m['email'] == key &&
          m['hash'] == _hash(m['salt'] as String, password)) {
        await (await _prefs).setString(_sessionKey, m['uid'] as String);
        final user = _user(m);
        _changes.add(user);
        return user;
      }
    }
    // Same answer for a wrong password and an unknown email, on purpose.
    throw const AuthException(
      'Email or password is not right. Check both and try again.',
    );
  }

  Future<void> signOut() async {
    await (await _prefs).remove(_sessionKey);
    _changes.add(null);
  }

  /// Removes the signed-in account from this phone for good.
  Future<void> deleteCurrent() async {
    final prefs = await _prefs;
    final uid = prefs.getString(_sessionKey);
    if (uid != null) {
      final rest = [for (final m in await _load()) if (m['uid'] != uid) m];
      await SecurePrefs.setString(_accountsKey, jsonEncode(rest));
    }
    await prefs.remove(_sessionKey);
    _changes.add(null);
  }
}
