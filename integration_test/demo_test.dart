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
    for (var i = 0; i < 26 && scrollTo && f.evaluate().isEmpty; i++) {
      await drag(t, -450, hold: 0.25);
      f = find.textContaining(text);
    }
    if (f.evaluate().isEmpty) {
      debugPrint('DEMO missing: $text');
      return false;
    }
    final target = last ? f.last : f.first;
    try {
      // Bring it to the upper part of the screen, so the tab bar is not on top of it.
      await Scrollable.ensureVisible(t.element(target), alignment: 0.3, duration: Duration.zero);
      await t.pump();
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
      'water' || 'track' => 'Community',
      'roads' => 'Driver',
      _ => 'Farmer',
    };
    await hold(t, 1.5);
    await tap(t, role, after: 6);

    switch (_scene) {
      case 'weather':
        await hold(t, 2.5);
        for (var i = 0; i < 6 && find.textContaining('Weather,').evaluate().isEmpty; i++) {
          await drag(t, -350, hold: 0.6);
        }
        await drag(t, -150, hold: 6);
      case 'disease':
        await tap(t, 'Send a video to a vet', scrollTo: true, after: 2.5);
        await tap(t, 'Quick check while you wait', scrollTo: true, after: 2);
        await tap(t, 'Cow', last: true, after: 1.2);
        await tap(t, 'Blisters or sores in the mouth', after: 1);
        await tap(t, 'Drooling / stringy saliva', after: 1);
        await tap(t, 'Blisters between the hooves', after: 1.4);
        for (var i = 0; i < 24 && find.textContaining('What this could be').evaluate().isEmpty; i++) {
          await drag(t, -450, hold: 0.25);
        }
        await drag(t, -120, hold: 5);
        await back(t);
        await back(t);
        await tap(t, 'Outbreaks', last: true, after: 3.5);
        await tap(t, 'Report an outbreak', after: 2);
        await tap(t, 'Livestock', last: true, after: 1.2);
        await tap(t, 'What are you seeing?', after: 1.6);
        await tap(t, 'Foot-and-Mouth Disease', last: true, after: 1.2);
        await tap(t, 'Urgent', last: true, after: 1.2);
        await tap(t, 'Send report', last: true, after: 4);
        await hold(t, 3);
      case 'water':
        await tap(t, 'Water', last: true, after: 4);
        await tap(t, 'Greater Durban', last: true, after: 2);
        await drag(t, -420, hold: 2);
        await drag(t, -420, hold: 2);
        await tap(t, 'My taps are dry', after: 3);
        await hold(t, 3);
      case 'cold':
        await tap(t, 'Sell', last: true, after: 2);
        await tap(t, 'Inventory and rooms', scrollTo: true, after: 3.5);
        debugPrint('DEMO hook cold');
        await hold(t, 8);
        await drag(t, 200, hold: 3);
        await drag(t, -250, hold: 4);
        debugPrint('DEMO hook restore');
      case 'roads':
        await tap(t, 'Roads', last: true, after: 4);
        for (var i = 0; i < 6 && find.textContaining('Live traffic').evaluate().isEmpty; i++) {
          await drag(t, -300, hold: 0.6);
        }
        await drag(t, -200, hold: 5);
      case 'track':
        await tap(t, 'Shop', last: true, after: 3);
        final menu = find.byIcon(Icons.menu_rounded);
        if (menu.evaluate().isNotEmpty) await t.tap(menu.first, warnIfMissed: false);
        await hold(t, 1.5);
        await tap(t, 'My orders', after: 2.5);
        await tap(t, 'Driver on the way', after: 5);
        await drag(t, -300, hold: 2);
      case 'impact':
        await tap(t, 'Me', last: true, after: 2);
        await tap(t, 'Impact evidence', scrollTo: true, after: 4);
        await drag(t, -350, hold: 3);
      // Earlier scenes (a delivery-led cut) are kept for the record.
      case 'health':
        await tap(t, 'Diagnose', last: true, after: 2);
        await tap(t, 'Outbreaks', last: true, after: 4);
        await tap(t, 'Water', last: true, after: 3);
      default:
        break;
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
