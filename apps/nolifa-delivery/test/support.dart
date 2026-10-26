import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'package:nolifa_delivery/app.dart';

// The test font (Ahem) renders every glyph a full em wide, so text rows
// overflow here that fit fine on a device. Ignore only those.
void ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

/// The app's real wiring with Supabase off: accounts live on the phone, and the
/// market and water data sit in memory so each test starts clean.
List<Override> deviceOverrides() => [
  ...dropOverrides,
  marketStartsLiveProvider.overrideWithValue(false),
  supabaseReadyProvider.overrideWithValue(false),
  marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
  waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
];

/// Opens the app on a phone-sized screen. Pass [keepStorage] to relaunch on
/// top of what the last launch saved.
Future<ProviderContainer> launch(
  WidgetTester tester, {
  bool keepStorage = false,
}) async {
  ignoreFontOverflow();
  if (!keepStorage) SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: deviceOverrides(), child: const NolifaDeliveryApp()),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(NolifaDeliveryApp)));
}

/// Runs a couple of seconds of frames. One long pump is not enough: timers
/// fire in the first frame and the animations they start only tick in later ones.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Tears the app down and lets the last timers run out.
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await settle(tester);
  await tester.enterText(field, value);
  await tester.pump();
}

/// Creates an account through the screens, the way a person would.
Future<void> signUpThroughScreens(
  WidgetTester tester, {
  String name = 'Thandi Mkhize',
  String email = 'thandi@example.com',
  String password = 'umlazi-2026',
}) async {
  await tapText(tester, 'Create an account');
  await fill(tester, 'Your name', name);
  await fill(tester, 'Email', email);
  await fill(tester, 'Password (8+ characters)', password);
  await tapText(tester, 'Create account');
}

/// Gets past the three welcome cards.
Future<void> finishOnboarding(WidgetTester tester) async {
  await tapText(tester, 'Skip');
}

/// The hub's bottom navigation bar.
Finder navBar(WidgetTester tester) {
  final hub = find.descendant(
    of: find.byType(MarketHub),
    matching: find.byType(Scaffold),
  );
  return find.byWidget(tester.widget<Scaffold>(hub.first).bottomNavigationBar!);
}

/// Signs out the way a person does: menu button on Shop, then Sign out.
Future<void> signOutViaMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await settle(tester);
  await tapText(tester, 'Sign out');
  await settle(tester);
}
