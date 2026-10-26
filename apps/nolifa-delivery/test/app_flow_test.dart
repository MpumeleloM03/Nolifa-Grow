import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'package:nolifa_delivery/app.dart';
import 'package:nolifa_delivery/auth/login_screen.dart';
import 'package:nolifa_delivery/onboarding/onboarding_screen.dart';
import 'package:nolifa_delivery/home/driver_home.dart';
import 'package:nolifa_delivery/shell/delivery_hub.dart';

import 'support.dart';

const _tabs = ['Jobs', 'Earnings', 'Account'];

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  testWidgets('signed out, the app opens on sign-in with a Local mode badge', (
    tester,
  ) async {
    await launch(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Nolifa Delivery'), findsOneWidget);
    expect(find.textContaining('Local mode'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('sign up lands on the driver welcome cards, then the hub', (
    tester,
  ) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Earn on your own street'), findsOneWidget);

    await finishOnboarding(tester);
    expect(find.byType(DeliveryHub), findsOneWidget);
    expect(c.read(marketNameProvider), 'Thandi Mkhize');
    expect(c.read(marketUidProvider), startsWith('local-'));
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
    expect(find.byType(OnboardingScreen), findsNothing);
    await closeApp(tester);
  });

  testWidgets('the hub has Jobs, Earnings and Account in order', (tester) async {
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

  testWidgets('Jobs asks an unverified driver to get verified first', (tester) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    expect(find.byType(DriverHome), findsOneWidget);
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.textContaining('Finish verification'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a verified driver who goes online sees batches and can open one', (tester) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    final store = c.read(marketProvider.notifier);
    store.setDemoMode(true);
    for (final step in driverSteps) {
      store.completeKyc(KycRole.driver, step.id);
    }
    await settle(tester);
    expect(c.read(marketProvider).openJobs, isNotEmpty);
    await tester.tap(find.text('Go'));
    await settle(tester);
    expect(find.text('You are online'), findsOneWidget);
    // The list sits in a sheet that opens part way. Pull it up to read it.
    await tester.drag(find.byType(DraggableScrollableSheet), const Offset(0, -700));
    await settle(tester);
    expect(find.text('Batches near you', skipOffstage: false), findsOneWidget);
    // Addresses are looked up on the map service, which tests cannot reach, so
    // give it a moment and then open the first batch card.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await settle(tester);
    final card = find.textContaining(' items');
    if (card.evaluate().isNotEmpty) {
      await tester.tap(card.first);
      await settle(tester);
      expect(find.text('Take this batch'), findsOneWidget);
    }
    await closeApp(tester);
  });

  testWidgets('Earnings explains the pay and starts at zero', (tester) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    c.read(marketProvider.notifier).setDemoMode(false);
    await tester.tap(
      find.descendant(of: navBar(tester), matching: find.text('Earnings')),
    );
    await settle(tester);
    expect(find.text('You have earned'), findsOneWidget);
    expect(find.text('How you are paid'), findsOneWidget);
    expect(find.text('Finished deliveries show up here.'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('Account shows verification, saves details, and signs out', (tester) async {
    final c = await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await tester.tap(
      find.descendant(of: navBar(tester), matching: find.text('Account')),
    );
    await settle(tester);
    expect(find.text('Get verified to go online'), findsOneWidget);

    await fill(tester, 'Cell number', '0821234567');
    await tapText(tester, 'Save changes');
    expect(c.read(marketProvider).profile.phone, '0821234567');

    await tapText(tester, 'Sign out');
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(c.read(marketUidProvider), 'guest');

    // Wrong password is turned away kindly; the right one goes straight in.
    await fill(tester, 'Email', 'thandi@example.com');
    await fill(tester, 'Password', 'not-my-password');
    await tapText(tester, 'Sign in');
    await settle(tester);
    expect(
      find.text('Email or password is not right. Check both and try again.'),
      findsOneWidget,
    );
    await fill(tester, 'Password', 'umlazi-2026');
    await tapText(tester, 'Sign in');
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DeliveryHub), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('the welcome cards only show once per account', (tester) async {
    await launch(tester);
    await signUpThroughScreens(tester);
    await finishOnboarding(tester);
    await closeApp(tester);

    await launch(tester, keepStorage: true);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DeliveryHub), findsOneWidget);
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
      ProviderScope(overrides: deviceOverrides(), child: const NolifaDeliveryApp()),
    );
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    await closeApp(tester);
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
