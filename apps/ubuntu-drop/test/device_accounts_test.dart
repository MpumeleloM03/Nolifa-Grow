import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecurePrefs, SecureBox;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_drop/auth/auth_service.dart';
import 'package:ubuntu_drop/auth/auth_user.dart';

AuthService phone() => AuthService(useCloud: false);

Future<String> problemWith(Future<void> Function() action) async {
  try {
    await action();
  } on AuthException catch (e) {
    return e.message;
  }
  fail('expected a sign-in problem');
}

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the password is never stored, only a salted hash', () async {
    await phone().signUp(
      name: 'Thandi',
      email: 'thandi@example.com',
      password: 'umlazi-2026',
    );
    final raw = (await SharedPreferences.getInstance()).getString('drop_accounts')!;
    // On the phone the whole account list is sealed: no email, name or hash shows.
    expect(raw, startsWith('enc1:'));
    expect(raw, isNot(contains('thandi@example.com')));
    expect(raw, isNot(contains('"hash"')));
    final stored = (await SecurePrefs.getString('drop_accounts'))!;
    expect(stored, isNot(contains('umlazi-2026')));
    expect(stored, contains('"hash"'));
    expect(stored, contains('"salt"'));
  });

  test('two accounts with the same password get different hashes', () async {
    final auth = phone();
    await auth.signUp(name: 'A', email: 'a@example.com', password: 'same-pass-1');
    await auth.signUp(name: 'B', email: 'b@example.com', password: 'same-pass-1');
    final stored = (await SecurePrefs.getString('drop_accounts'))!;
    final hashes = RegExp(r'"hash":"([^"]+)"')
        .allMatches(stored)
        .map((m) => m.group(1))
        .toSet();
    expect(hashes.length, 2);
  });

  test('email is not case sensitive and cannot be used twice', () async {
    final auth = phone();
    await auth.signUp(
      name: 'Thandi',
      email: 'Thandi@Example.com',
      password: 'umlazi-2026',
    );
    final msg = await problemWith(
      () => auth.signUp(
        name: 'Other',
        email: ' thandi@example.com ',
        password: 'another-pass-2',
      ),
    );
    expect(msg, contains('already exists'));
    await auth.signOut();
    await auth.signIn('THANDI@example.com', 'umlazi-2026');
    expect((await auth.authState().first)?.name, 'Thandi');
  });

  test('a wrong password and an unknown email get the same answer', () async {
    final auth = phone();
    await auth.signUp(
      name: 'Thandi',
      email: 'thandi@example.com',
      password: 'umlazi-2026',
    );
    await auth.signOut();
    final wrongPassword = await problemWith(
      () => auth.signIn('thandi@example.com', 'nope-nope'),
    );
    final unknownEmail = await problemWith(
      () => auth.signIn('nobody@example.com', 'umlazi-2026'),
    );
    expect(wrongPassword, unknownEmail);
    expect(wrongPassword, contains('Check both'));
    expect(await auth.authState().first, isNull);
  });

  test('bad input is turned away in plain words', () async {
    final auth = phone();
    expect(
      await problemWith(
        () => auth.signUp(name: 'T', email: 'not-an-email', password: 'abcdef12'),
      ),
      'That email address does not look right.',
    );
    expect(
      await problemWith(
        () => auth.signUp(name: 'T', email: 't@example.com', password: 'abc'),
      ),
      'Use at least 8 characters.',
    );
    expect(
      await problemWith(
        () =>
            auth.signUp(name: '  ', email: 't@example.com', password: 'abcdef12'),
      ),
      contains('Add your name'),
    );
    expect(await auth.authState().first, isNull);
  });

  test('the session survives closing the app, and sign out ends it', () async {
    await phone().signUp(
      name: 'Thandi',
      email: 'thandi@example.com',
      password: 'umlazi-2026',
    );
    final reopened = phone();
    final user = await reopened.authState().first;
    expect(user?.email, 'thandi@example.com');
    expect(user?.uid, startsWith('local-'));
    await reopened.signOut();
    expect(await phone().authState().first, isNull);
  });

  test('the sign-in stream reports each change as it happens', () async {
    final auth = phone();
    final seen = <String?>[];
    final sub = auth.authState().listen((u) => seen.add(u?.name));
    await Future<void>.delayed(Duration.zero);
    await auth.signUp(
      name: 'Thandi',
      email: 'thandi@example.com',
      password: 'umlazi-2026',
    );
    await auth.signOut();
    await auth.signIn('thandi@example.com', 'umlazi-2026');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [null, 'Thandi', null, 'Thandi']);
  });

  test('password reset says why it cannot work without the shared database', () async {
    final msg = await problemWith(() => phone().sendReset('t@example.com'));
    expect(msg, contains('shared database'));
  });

  test(
    'on-device accounts never carry the water provider permission',
    () async {
      final auth = phone();
      await auth.signUp(
        name: 'Thandi',
        email: 'thandi@example.com',
        password: 'umlazi-2026',
      );
      expect(await auth.utilityClaim(), isFalse);
    },
  );

  test('the avatar shows the first letter of the name', () {
    expect(
      const AuthUser(uid: 'u', name: ' thandi', email: 'x@y.za').initial,
      'T',
    );
    expect(const AuthUser(uid: 'u', name: '', email: 'x@y.za').initial, 'X');
    expect(const AuthUser(uid: 'u', name: '', email: '').initial, '?');
  });
}
