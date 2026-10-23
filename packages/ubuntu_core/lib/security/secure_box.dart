import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypts what the apps keep on the phone. Driver and farm documents, health
/// records, accounts and orders are special personal information under POPIA,
/// so they are stored sealed with AES-256-GCM. The key lives in the iOS
/// Keychain (or the Android Keystore) and never in the same place as the data.
///
/// Stored text looks like `enc1:<base64 of nonce, ciphertext and tag>`.
/// Anything without that prefix is older plain text: it is still read, and it
/// is sealed the next time it is saved.
abstract class SecureBox {
  static const prefix = 'enc1:';

  Future<String> seal(String plain);

  /// The plain text, or null if it cannot be opened (wrong key, tampered).
  Future<String?> open(String stored);

  /// The box the apps use. Tests replace it with [AesSecureBox.withKey].
  static SecureBox instance = AesSecureBox.keychain();
}

class AesSecureBox implements SecureBox {
  final Future<SecretKey> Function() _key;
  final _algo = AesGcm.with256bits();

  AesSecureBox._(this._key);

  /// A box with a fixed key, for tests.
  AesSecureBox.withKey(List<int> key) : _key = (() async => SecretKey(key));

  /// A box whose key is generated once and kept in the Keychain or Keystore.
  factory AesSecureBox.keychain() {
    const store = FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    );
    SecretKey? cached;
    Future<SecretKey> load() async {
      if (cached != null) return cached!;
      try {
        final saved = await store.read(key: 'nolifa_data_key');
        if (saved != null) return cached = SecretKey(base64Decode(saved));
        final fresh = List<int>.generate(32, (_) => Random.secure().nextInt(256));
        await store.write(key: 'nolifa_data_key', value: base64Encode(fresh));
        return cached = SecretKey(fresh);
      } catch (e) {
        // No key store (for example an unsupported platform). Use a key that
        // lasts only for this run rather than writing data in the clear.
        debugPrint('secure storage: no key store, using a temporary key: $e');
        return cached = SecretKey(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
      }
    }

    return AesSecureBox._(load);
  }

  @override
  Future<String> seal(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: await _key());
    return SecureBox.prefix + base64Encode(box.concatenation());
  }

  @override
  Future<String?> open(String stored) async {
    if (!stored.startsWith(SecureBox.prefix)) return stored; // older plain text
    try {
      final bytes = base64Decode(stored.substring(SecureBox.prefix.length));
      final box = SecretBox.fromConcatenation(bytes,
          nonceLength: _algo.nonceLength, macLength: _algo.macAlgorithm.macLength);
      return utf8.decode(await _algo.decrypt(box, secretKey: await _key()));
    } catch (e) {
      debugPrint('secure storage: could not open a saved value: $e');
      return null;
    }
  }
}

/// A box that stores text as it is. Only for tests that read storage directly.
class PlainSecureBox implements SecureBox {
  const PlainSecureBox();
  @override
  Future<String> seal(String plain) async => plain;
  @override
  Future<String?> open(String stored) async => stored;
}

/// SharedPreferences for strings, sealed with [SecureBox.instance]. Use it for
/// anything personal: accounts, health records, documents, orders.
class SecurePrefs {
  static Future<String?> getString(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null ? null : SecureBox.instance.open(raw);
  }

  static Future<void> setString(String key, String value) async {
    final sealed = await SecureBox.instance.seal(value);
    await (await SharedPreferences.getInstance()).setString(key, sealed);
  }

  static Future<void> remove(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
