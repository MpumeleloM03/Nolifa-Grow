// Opens the real app on a phone or simulator, signs in as one of the demo accounts and walks
// every tab and the main screens behind them, the way a person would. Any Flutter error on the
// way (an overflow stripe, a red error screen, an exception in a build) fails the run and is
// listed with the step it happened on.
//
//   flutter test integration_test/sweep_test.dart -d <device> --flavor nolifa \
//     --dart-define=QA_ROLE=farmer|customer|driver --dart-define=QA_EMAIL=... --dart-define=QA_PASSWORD=...
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nolifa_grow/edition.dart';
import 'package:nolifa_grow/main.dart' as app;

const _role = String.fromEnvironment('QA_ROLE', defaultValue: 'farmer');
const _email = String.fromEnvironment('QA_EMAIL');
const _password = String.fromEnvironment('QA_PASSWORD');
const _grow = bool.fromEnvironment('QA_GROW');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  final skipped = <String>[];
  var step = 'start';

  Future<void> settle(WidgetTester t, [int ms = 1200]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> scrollDown(WidgetTester t, {double dy = -500}) async {
    final s = find.byType(Scrollable);
    if (s.evaluate().isEmpty) return;
    try {
      await t.drag(s.first, Offset(0, dy), warnIfMissed: false);
    } catch (_) {}
    await settle(t, 500);
  }

  Future<bool> tapText(WidgetTester t, String text, {bool last = false, bool scrollTo = false}) async {
    step = 'tap "$text"';
    var f = find.text(text);
    if (f.evaluate().isEmpty) f = find.textContaining(text);
    if (f.evaluate().isEmpty && scrollTo) {
      for (var i = 0; i < 8 && f.evaluate().isEmpty; i++) {
        await scrollDown(t);
        f = find.textContaining(text);
      }
    }
    if (f.evaluate().isEmpty) {
      skipped.add(step);
      return false;
    }
    final target = last ? f.last : f.first;
    try {
      await t.ensureVisible(target);
    } catch (_) {}
    await t.tap(target, warnIfMissed: false);
    await settle(t);
    return true;
  }

  Future<void> back(WidgetTester t) async {
    step = 'back';
    final b = find.byIcon(Icons.arrow_back_ios_new_rounded);
    final b2 = find.byIcon(Icons.chevron_left_rounded);
    final b3 = find.byIcon(Icons.close_rounded);
    final b4 = find.byIcon(Icons.arrow_back_rounded);
    final b5 = find.byType(BackButton);
    for (final f in [b, b2, b4, b5, b3]) {
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.first, warnIfMissed: false);
        await settle(t);
        return;
      }
    }
    final nav = find.byType(Navigator);
    if (nav.evaluate().isNotEmpty) {
      await Navigator.maybePop(t.element(nav.first));
      await settle(t);
    }
  }

  /// Opens a screen, scrolls through it, and comes back.
  Future<void> visit(WidgetTester t, String text, {bool scrollTo = false}) async {
    if (await tapText(t, text, scrollTo: scrollTo)) {
      step = 'scroll "$text"';
      await scrollDown(t);
      await scrollDown(t);
      await back(t);
    }
  }

  /// Opens each item whose text matches (an order id), looks around and comes back.
  Future<void> openEach(WidgetTester t, String pattern, {int max = 6}) async {
    final n = find.textContaining(pattern).evaluate().length.clamp(0, max);
    for (var i = 0; i < n; i++) {
      step = 'open $pattern #${i + 1}';
      final f = find.textContaining(pattern);
      if (f.evaluate().length <= i) break;
      try {
        await t.ensureVisible(f.at(i));
      } catch (_) {}
      await t.tap(f.at(i), warnIfMissed: false);
      await settle(t, 1800);
      await scrollDown(t);
      await scrollDown(t);
      await back(t);
    }
  }

  testWidgets('walk the $_role account through the app', (tester) async {
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString().split('\n').first;
      errors.add('[$step] $msg');
    };
    if (_grow) AppEdition.current = Edition.grow;
    await app.runNolifa(_grow ? Edition.grow : Edition.nolifa);
    await settle(tester, 3000);

    // Sign in.
    step = 'sign in';
    if (find.text('Sign in').evaluate().isNotEmpty) {
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), _email);
      await tester.enterText(fields.at(1), _password);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sign in').last, warnIfMissed: false);
      await settle(tester, 6000);
    }
    expect(find.text('Sign in'), findsNothing, reason: 'signing in worked');

    final tabs = switch (_role) {
      'customer' => ['Shop', 'Water', 'Me'],
      'driver' => ['Jobs', 'Roads', 'Earnings', 'Me'],
      _ => ['Diagnose', 'Outbreaks', 'Water', 'Sell', 'Me'],
    };
    for (final tab in tabs) {
      step = 'tab $tab';
      if (!await tapText(tester, tab, last: true)) continue;
      await scrollDown(tester);
      await scrollDown(tester, dy: -900);
      await scrollDown(tester, dy: 1500);
    }

    if (_role == 'farmer') {
      await tapText(tester, 'Sell', last: true);
      await visit(tester, 'Parcel label', scrollTo: true);
      await visit(tester, 'Scan to send out', scrollTo: true);
      await visit(tester, 'Follow the driver', scrollTo: true);
      await tapText(tester, 'Sell', last: true);
      await visit(tester, 'Inventory and rooms', scrollTo: true);
      await visit(tester, 'Truck hire', scrollTo: true);
      await visit(tester, 'Plans', scrollTo: true);
      await visit(tester, 'Wallet', scrollTo: true);
      if (await tapText(tester, 'Add stock', scrollTo: true)) {
        await settle(tester);
        await back(tester);
      }
      await tapText(tester, 'Me', last: true);
      await visit(tester, 'Notifications');
      await visit(tester, 'Farm logo and store picture', scrollTo: true);
      await tapText(tester, 'Diagnose', last: true);
      await visit(tester, 'Your herd', scrollTo: true);
      await tapText(tester, 'Outbreaks', last: true);
      await tapText(tester, 'Water', last: true);
    } else if (_role == 'customer') {
      await tapText(tester, 'Shop', last: true);
      step = 'menu';
      final menu = find.byIcon(Icons.menu_rounded);
      if (menu.evaluate().isNotEmpty) {
        await tester.tap(menu.first, warnIfMissed: false);
        await settle(tester);
        if (await tapText(tester, 'My orders')) {
          await openEach(tester, 'UD-');
          await back(tester);
        }
        await back(tester);
      }
      await tapText(tester, 'Shop', last: true);
      if (await tapText(tester, 'Fatboy Butcheries', scrollTo: true)) {
        step = 'farm page';
        await scrollDown(tester);
        await scrollDown(tester);
        await back(tester);
      }
      await tapText(tester, 'Me', last: true);
      await visit(tester, 'Notifications');
    } else {
      await tapText(tester, 'Jobs', last: true);
      await openEach(tester, 'UD-');
      await visit(tester, 'Road alerts');
      await tapText(tester, 'Wallet');
      await back(tester);
      await tapText(tester, 'Earnings', last: true);
      await tapText(tester, 'Me', last: true);
      await visit(tester, 'Notifications');
    }

    step = 'end';
    if (skipped.isNotEmpty) debugPrint('SWEEP skipped (not on screen): ${skipped.toSet().join('; ')}');
    if (errors.isNotEmpty) debugPrint('SWEEP ERRORS:\n${errors.toSet().join('\n')}');
    expect(errors.toSet(), isEmpty, reason: 'no overflow stripes or red errors');
  });
}
