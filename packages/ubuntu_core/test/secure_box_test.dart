import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = List<int>.generate(32, (i) => i);

  group('sealing', () {
    test('what goes in comes out, and the stored text hides it', () async {
      final box = AesSecureBox.withKey(key);
      const secret = '{"idNumber":"9001015800086","vehicle":"Toyota Hilux"}';
      final sealed = await box.seal(secret);
      expect(sealed, startsWith('enc1:'));
      expect(sealed, isNot(contains('9001015800086')));
      expect(sealed, isNot(contains('Hilux')));
      expect(await box.open(sealed), secret);
    });

    test('the same text seals differently each time, so patterns do not leak', () async {
      final box = AesSecureBox.withKey(key);
      expect(await box.seal('same'), isNot(await box.seal('same')));
    });

    test('a different key cannot open it', () async {
      final sealed = await AesSecureBox.withKey(key).seal('private');
      final other = AesSecureBox.withKey(List<int>.generate(32, (i) => 255 - i));
      expect(await other.open(sealed), isNull);
    });

    test('a changed byte is caught, not read as something else', () async {
      final box = AesSecureBox.withKey(key);
      final sealed = await box.seal('{"balance":100}');
      final bytes = base64Decode(sealed.substring(5));
      bytes[bytes.length ~/ 2] ^= 1;
      expect(await box.open('enc1:${base64Encode(bytes)}'), isNull);
    });

    test('older plain text still reads, and is sealed on the next save', () async {
      final box = AesSecureBox.withKey(key);
      expect(await box.open('{"old":true}'), '{"old":true}');
    });
  });

  group('SecurePrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SecureBox.instance = AesSecureBox.withKey(key);
    });

    test('writes sealed text to the phone and reads it back', () async {
      await SecurePrefs.setString('k', 'health record: foot-and-mouth');
      final raw = (await SharedPreferences.getInstance()).getString('k')!;
      expect(raw, startsWith('enc1:'));
      expect(raw, isNot(contains('foot-and-mouth')));
      expect(await SecurePrefs.getString('k'), 'health record: foot-and-mouth');
    });

    test('data saved before encryption existed is still readable', () async {
      SharedPreferences.setMockInitialValues({'old': '{"plain":1}'});
      expect(await SecurePrefs.getString('old'), '{"plain":1}');
      await SecurePrefs.setString('old', '{"plain":2}');
      expect((await SharedPreferences.getInstance()).getString('old'), startsWith('enc1:'));
    });

    test('the market storage the apps use is sealed too', () async {
      await PrefsKv().write('market_x', '{"orders":[{"pin":"4821"}]}');
      final raw = (await SharedPreferences.getInstance()).getString('market_x')!;
      expect(raw, isNot(contains('4821')));
      expect(await PrefsKv().read('market_x'), '{"orders":[{"pin":"4821"}]}');
    });

    test('a value that cannot be opened reads as empty rather than crashing', () async {
      await SecurePrefs.setString('k', 'secret');
      SecureBox.instance = AesSecureBox.withKey(List<int>.generate(32, (i) => 99));
      expect(await SecurePrefs.getString('k'), isNull);
    });
  });

  group('the key', () {
    test('is made once, kept in the key store, and reused', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final a = AesSecureBox.keychain();
      final sealed = await a.seal('hello');
      // A new box (like the next launch) finds the same key in the store.
      final b = AesSecureBox.keychain();
      expect(await b.open(sealed), 'hello');
    });
  });
}
