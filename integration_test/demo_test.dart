// A paced walk through the app for the judges' video. It signs in with the demo buttons and
// shows one scene per run: health (farmer: diagnosis, vets, outbreak map, stock), order
// (customer), pack (farmer dispatches) and drive (driver).
//
//   flutter test integration_test/demo_test.dart -d <device> --flavor nolifa --dart-define=QA_SCENE=health
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nolifa_grow/edition.dart';
import 'package:nolifa_grow/main.dart' as app;

const _scene = String.fromEnvironment('QA_SCENE', defaultValue: 'health');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  var step = 'start';

  Future<void> hold(WidgetTester t, double seconds) async {
    for (var i = 0; i < (seconds * 10).round(); i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<bool> tap(WidgetTester t, String text, {bool last = false, double after = 1.6, bool scrollTo = false}) async {
    step = 'tap "$text"';
    debugPrint('DEMO step $step');
    var f = find.text(text);
    if (f.evaluate().isEmpty) f = find.textContaining(text);
    for (var i = 0; i < 8 && scrollTo && f.evaluate().isEmpty; i++) {
      await drag(t, -450);
      f = find.textContaining(text);
    }
    if (f.evaluate().isEmpty) {
      debugPrint('DEMO missing: $text');
      return false;
    }
    final target = last ? f.last : f.first;
    try {
      await t.ensureVisible(target);
    } catch (_) {}
    await t.tap(target, warnIfMissed: false);
    await hold(t, after);
    return true;
  }

  Future<void> back(WidgetTester t) async {
    for (final f in [find.byIcon(Icons.arrow_back_ios_new_rounded), find.byIcon(Icons.arrow_back_rounded), find.byType(BackButton), find.byIcon(Icons.close_rounded)]) {
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.first, warnIfMissed: false);
        await hold(t, 1.2);
        return;
      }
    }
  }

  Future<void> signOut(WidgetTester t) async {
    step = 'sign out';
    for (var i = 0; i < 4 && find.text('Me').evaluate().isEmpty; i++) {
      await back(t);
    }
    await tap(t, 'Me', last: true, after: 1.2);
    await tap(t, 'Sign out', scrollTo: true, after: 1);
    for (var i = 0; i < 40 && find.text('Sign in').evaluate().isEmpty; i++) {
      await hold(t, 0.5);
    }
    await hold(t, 1.5);
  }

  testWidgets('demo $_scene', (t) async {
    FlutterError.onError = (d) => errors.add('[$step] ${d.exceptionAsString().split('\n').first}');
    await app.runNolifa(Edition.nolifa);
    await hold(t, 3);
    debugPrint('DEMO begin');
    step = 'sign in';
    final role = switch (_scene) {
      'order' => 'Community',
      'drive' => 'Driver',
      _ => 'Farmer',
    };
    await hold(t, 1.5);
    await tap(t, role, after: 6);

    switch (_scene) {
      case 'health':
        await tap(t, 'Diagnose', last: true, after: 2);
        await drag(t, -350, hold: 1.5);
        await tap(t, 'Crop health AI: my crops', after: 3);
        await drag(t, -400, hold: 1.5);
        await back(t);
        await tap(t, 'Send a video to a vet', after: 3);
        await back(t);
        await tap(t, 'Outbreaks', last: true, after: 4);
        await drag(t, -300, hold: 2);
        await tap(t, 'Water', last: true, after: 3);
        await drag(t, -400, hold: 1.5);
        await tap(t, 'Sell', last: true, after: 2);
        await tap(t, 'Inventory and rooms', scrollTo: true, after: 3);
        await drag(t, -450, hold: 2);
        await back(t);
      case 'order':
        await tap(t, 'Shop', last: true, after: 3);
        await drag(t, -300, hold: 1);
        await tap(t, 'Order now', after: 3);
        await drag(t, -300, hold: 1);
        await tap(t, 'Add', after: 1.2);
        await tap(t, 'Checkout', after: 3);
        await drag(t, -400, hold: 1.5);
        await tap(t, 'Cash on delivery', scrollTo: true, after: 1.5);
        await tap(t, 'Pay R', scrollTo: true, after: 5);
        await hold(t, 3);
      case 'pack':
        await tap(t, 'Sell', last: true, after: 3);
        await drag(t, -350, hold: 1.5);
        await tap(t, 'Parcel label', scrollTo: true, after: 3.5);
        await back(t);
        await tap(t, 'Packed, request driver', scrollTo: true, after: 3);
        await drag(t, -300, hold: 2);
      case 'drive':
        await hold(t, 3);
        await tap(t, 'Go', after: 5);
        await drag(t, -250, hold: 1.5);
        await tap(t, 'drop', after: 3);
        await tap(t, 'Take this batch', after: 6);
        await drag(t, -250, hold: 3);
        await back(t);
        await tap(t, 'Roads', last: true, after: 3);
        await tap(t, 'Earnings', last: true, after: 3);
    }
    for (final e in errors.toSet()) {
      debugPrint('DEMO ERROR $e');
    }
    debugPrint('DEMO errors: ${errors.toSet().length}');
  });
}

Future<void> drag(WidgetTester t, double dy, {double hold = 0.8}) async {
  final s = find.byType(Scrollable);
  if (s.evaluate().isNotEmpty) {
    try {
      await t.drag(s.first, Offset(0, dy), warnIfMissed: false);
    } catch (_) {}
  }
  for (var i = 0; i < (hold * 10).round(); i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
