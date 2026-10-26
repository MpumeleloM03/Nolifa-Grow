import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'package:ubuntu_drop/app.dart';
import 'package:ubuntu_drop/auth/auth_service.dart';
import 'package:ubuntu_drop/auth/auth_user.dart';
import 'package:ubuntu_drop/auth/login_screen.dart';
import 'package:ubuntu_drop/onboarding/onboarding_screen.dart';
import 'package:ubuntu_drop/shell/drop_hub.dart';
import 'package:ubuntu_drop/shell/welcome_back.dart';

import 'support.dart';

const _tabs = ['Shop', 'Water', 'Alerts'];

/// A signed-in account that answers the water provider question however the
/// test needs, without touching Supabase.
class _FakeAuth extends AuthService {
  _FakeAuth({required this.user, required this.utility})
    : super(useCloud: false);
  final AuthUser? user;
  final bool utility;

  @override
  Stream<AuthUser?> authState() => Stream.value(user);

  @override
  Future<bool> utilityClaim() async => utility;
}

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  testWidgets('signed out, the app opens on sign-in with a Local mode badge', (
    tester,
  ) async {
    await launch(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('Local mode'), findsOneWidget);
    // Reset by email needs Supabase, so the dead-end link is not offered.
    expect(find.text('Forgot password?'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('sign up lands on the welcome cards, then the hub', (
    tester,
  ) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('A community that stays fed'), findsOneWidget);

    await finishOnboarding(tester);
    expect(find.byType(DropHub), findsOneWidget);

    // The shared package now knows who this is.
    expect(c.read(marketNameProvider), 'Thandi Mkhize');
    expect(c.read(marketUidProvider), startsWith('local-'));
    expect(c.read(currentUserProvider)?.email, 'thandi@example.com');
    await closeApp(tester);
  });

  testWidgets('empty sign-up fields say what is missing and create nothing', (
    tester,
  ) async {
    await launch(tester);
    await tapText(tester, 'Create an account');
    await tapText(tester, 'Create account');
    expect(
      find.text('Add your name so neighbours know who you are.'),
      findsOneWidget,
    );
    expect(
      find.text('That email address does not look right.'),
      findsOneWidget,
    );
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    await closeApp(tester);
  });

  testWidgets('sign out, then back in with the same password; a wrong one is '
      'turned away kindly', (tester) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    // Sign out from the menu.
    await signOutViaMenu(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(c.read(marketUidProvider), 'guest');

    // Wrong password: stay put, say it plainly.
    await fill(tester, 'Email', 'thandi@example.com');
    await fill(tester, 'Password', 'not-my-password');
    await tapText(tester, 'Sign in');
    await settle(tester);
    expect(
      find.text('Email or password is not right. Check both and try again.'),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsOneWidget);

    // Right password: straight to the hub, no second tour.
    await fill(tester, 'Password', 'umlazi-2026');
    await tapText(tester, 'Sign in');
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DropHub), findsOneWidget);
    expect(c.read(marketNameProvider), 'Thandi Mkhize');
    await closeApp(tester);
  });

  testWidgets('the welcome cards only show once per account', (tester) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    final uid = (await SharedPreferences.getInstance()).getString(
      'drop_session',
    )!;
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarded_$uid'),
      isTrue,
    );
    await closeApp(tester);

    // Close the app and open it again on the same phone.
    await launch(tester, keepStorage: true);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DropHub), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a second neighbour on the same phone gets their own tour', (
    tester,
  ) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await signOutViaMenu(tester);

    await signUpThroughScreens(
      tester,
      name: 'Sipho Dlamini',
      email: 'sipho@example.com',
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('the hub has Shop, Water and Alerts in order', (
    tester,
  ) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    final labels = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: navBar(tester), matching: find.byType(Text)),
      ))
        t.data,
    ];
    expect(labels, _tabs);
    await closeApp(tester);
  });

  testWidgets('the Water tab shows the home community', (tester) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    // The tab bar label, not the page that may repeat the word.
    await tester.tap(
      find.descendant(of: navBar(tester), matching: find.text('Water')),
    );
    await settle(tester);
    expect(find.byType(WaterPage), findsOneWidget);
    expect(find.byType(ShopHomePage), findsNothing);
    // Strings only the Water page has, next to the home community.
    await tester.scrollUntilVisible(
      find.text('Community voice'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Community voice'), findsOneWidget);
    expect(find.textContaining('Umlazi'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('Shop is laid out like a food app: farms in bold, offerings, cart and menu', (
    tester,
  ) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    expect(find.byType(ShopHomePage), findsOneWidget);
    expect(find.text('Fresh near you'), findsOneWidget);
    expect(find.text('Farms near you'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('opening the app with low water pops up a Vote button that leads to Water', (
    tester,
  ) async {
    await launch(tester, waterPrompt: true);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await settle(tester);

    expect(find.textContaining('water is low'), findsWidgets);
    expect(find.text('Vote for help'), findsOneWidget);
    await tester.tap(find.text('Vote for help'));
    await settle(tester);
    expect(find.byType(WaterScreen), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('the low-water pop-up can be dismissed and does not return', (tester) async {
    await launch(tester, waterPrompt: true);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await settle(tester);
    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(find.text('Vote for help'), findsNothing);
    await tester.tap(
      find.descendant(of: navBar(tester), matching: find.text('Water')),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(of: navBar(tester), matching: find.text('Shop')),
    );
    await settle(tester);
    expect(find.text('Vote for help'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('opening the app sends a Welcome back notification with the customer name', (
    tester,
  ) async {
    final fake = FakeNotifier();
    await launch(tester, extra: [notifierProvider.overrideWithValue(fake)]);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(fake.sent, hasLength(1));
    expect(fake.sent.single.title, 'Welcome back, Thandi');
    expect(fake.sent.single.body, isNotEmpty);
    // Opening other pages does not send a second one.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(fake.sent, hasLength(1));
    await closeApp(tester);
  });

  test('the customer update leads with orders, then water', () {
    expect(customerUpdate(2, 'Umlazi water is low (33%)'), '2 orders are on the way. Umlazi water is low (33%).');
    expect(customerUpdate(1, null), '1 order is on the way.');
    expect(customerUpdate(0, null), 'Fresh produce is waiting from farms near you.');
  });

  testWidgets('the menu has orders, wallet, settings, trust and help', (
    tester,
  ) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    for (final t in [
      'My orders',
      'Wallet and receipts',
      'My savings',
      'Settings',
      'Trust and safety',
      'Help and support',
      'Sign out',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await closeApp(tester);
  });

  testWidgets('settings saves the delivery address and Shop shows it', (
    tester,
  ) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    expect(find.text('Set your address'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tapText(tester, 'Settings');
    await fill(tester, 'Delivery address', '12 Jacaranda Road');
    await fill(tester, 'Suburb or town', 'Umlazi');
    await tapText(tester, 'Save changes');
    expect(c.read(marketProvider).profile.address, '12 Jacaranda Road');

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await settle(tester);
    }
    expect(find.text('12 Jacaranda Road, Umlazi'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('unreadable saved accounts still reach sign-in', (tester) async {
    ignoreFontOverflow();
    SharedPreferences.setMockInitialValues({
      'drop_session': 'local-x',
      'drop_accounts': 'not json',
    });
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: deviceOverrides(), child: const NolifaDropApp()),
    );
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('the account sheet shows who you are and how to switch modes', (
    tester,
  ) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);

    // The menu carries the first initial, and leads to the account sheet.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    expect(find.text('T'), findsOneWidget);
    await tapText(tester, 'Account and app mode');

    expect(find.text('Thandi Mkhize'), findsWidgets);
    expect(find.text('thandi@example.com'), findsOneWidget);
    expect(find.text('You are in demo mode'), findsOneWidget);
    expect(find.textContaining('Trust and Safety'), findsWidgets);
    expect(find.text('Saved on this phone only'), findsOneWidget);
    expect(find.text('Sign out'), findsWidgets);
    await closeApp(tester);
  });

  group('water provider permission', () {
    ProviderContainer containerFor(AuthService auth) {
      final c = ProviderContainer(
        overrides: [
          ...deviceOverrides(),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    const person = AuthUser(uid: 'u1', name: 'Zanele', email: 'z@example.com');

    test('an account with the utility claim gets the provider desk', () async {
      final c = containerFor(_FakeAuth(user: person, utility: true));
      expect(c.read(waterUtilityProvider), isFalse); // until the token is read
      await pumpEventQueue(times: 50);
      expect(c.read(waterUtilityProvider), isTrue);
    });

    test('an ordinary account does not', () async {
      final c = containerFor(_FakeAuth(user: person, utility: false));
      expect(c.read(waterUtilityProvider), isFalse);
      await pumpEventQueue(times: 50);
      expect(c.read(waterUtilityProvider), isFalse);
    });

    test('signed out, nobody does, whatever the token says', () async {
      final c = containerFor(_FakeAuth(user: null, utility: true));
      expect(c.read(waterUtilityProvider), isFalse);
      await pumpEventQueue(times: 50);
      expect(c.read(waterUtilityProvider), isFalse);
      expect(c.read(marketUidProvider), 'guest');
    });
  });

  test('no em dashes in anything the app can show', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('—'))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
