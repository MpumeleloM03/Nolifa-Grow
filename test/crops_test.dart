import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecurePrefs, SecureBox;
import 'package:nolifa_grow/crops/crop_models.dart';
import 'package:nolifa_grow/crops/crop_store.dart';
import 'package:nolifa_grow/crops/my_crops_screen.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/shell/home_tab.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 22, 9);

CropPlot plot({
  String crop = 'Tomato',
  int daysAgo = 40,
  double area = 100,
  SprinklerPlan sprinkler = const SprinklerPlan(),
  List<HealthCheck> checks = const [],
}) =>
    CropPlot(
      id: 'p1',
      crop: crop,
      name: 'North field',
      plantedOn: _now.subtract(Duration(days: daysAgo)),
      areaM2: area,
      sprinkler: sprinkler,
      checks: checks,
    );

void ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  group('crop advisor', () {
    test('a fresh plot is a seedling with the full cycle to go', () {
      final o = CropAdvisor.assess(plot(daysAgo: 0), _now);
      expect(o.stage, 'Seedling');
      expect(o.progress, 0);
      expect(o.ready, isFalse);
      expect(o.confidence, 'Low');
      expect(o.advice.any((a) => a.contains('Scan a leaf')), isTrue);
    });

    test('a well-watered, healthy crop stays close to the calendar', () {
      const good = SprinklerPlan(enabled: true, litresPerMinute: 10, minutesPerRun: 60, startHours: const [6]);
      final checks = [HealthCheck(_now.subtract(const Duration(days: 1)), 'Healthy', 'green')];
      final o = CropAdvisor.assess(plot(daysAgo: 40, sprinkler: good, checks: checks), _now);
      // Tomato: 85 days. 40 days in, so about 45 to go.
      expect(o.rate, 1.0);
      expect(o.daysToHarvest, inInclusiveRange(44, 46));
      expect(o.daysToHarvestHigh, greaterThan(o.daysToHarvest));
      expect(o.stage, 'Flowering');
      expect(o.healthScore, greaterThan(90));
    });

    test('an urgent disease slows the crop and pushes harvest later', () {
      final base = CropAdvisor.assess(plot(daysAgo: 40), _now);
      final sick = CropAdvisor.assess(
          plot(daysAgo: 40, checks: [HealthCheck(_now.subtract(const Duration(days: 1)), 'Late Blight', 'red')]),
          _now);
      expect(sick.rate, lessThan(base.rate));
      expect(sick.daysToHarvest, greaterThan(base.daysToHarvest));
      expect(sick.healthScore, lessThan(50));
      expect(sick.advice.any((a) => a.contains('urgent')), isTrue);
    });

    test('old trouble stops counting after about two weeks', () {
      final recent = CropAdvisor.assess(
          plot(checks: [HealthCheck(_now.subtract(const Duration(days: 1)), 'Rust', 'orange')]), _now);
      final old = CropAdvisor.assess(
          plot(checks: [HealthCheck(_now.subtract(const Duration(days: 20)), 'Rust', 'orange')]), _now);
      expect(old.rate, greaterThanOrEqualTo(recent.rate));
      expect(old.advice.any((a) => a.contains('days ago')), isTrue);
    });

    test('too little water slows growth, too much is flagged', () {
      const dry = SprinklerPlan(enabled: true, litresPerMinute: 5, minutesPerRun: 20);
      const flood = SprinklerPlan(enabled: true, litresPerMinute: 30, minutesPerRun: 120);
      final d = CropAdvisor.assess(plot(daysAgo: 50, sprinkler: dry), _now);
      final f = CropAdvisor.assess(plot(daysAgo: 50, sprinkler: flood), _now);
      expect(d.waterRatio!, lessThan(0.6));
      expect(d.rate, lessThan(1.0));
      expect(d.advice.any((a) => a.contains('Run it longer')), isTrue);
      expect(f.waterRatio!, greaterThan(1.5));
      expect(f.advice.any((a) => a.contains('root rot')), isTrue);
    });

    test('past the cycle it is ready, and later overdue', () {
      final ready = CropAdvisor.assess(plot(crop: 'Spinach', daysAgo: 50), _now);
      expect(ready.ready, isTrue);
      expect(ready.stage, 'Ready to harvest');
      expect(ready.daysToHarvest, 0);
      final overdue = CropAdvisor.assess(plot(crop: 'Spinach', daysAgo: 120), _now);
      expect(overdue.overdue, isTrue);
      expect(overdue.advice.any((a) => a.contains('Past the best harvest window')), isTrue);
    });

    test('more evidence narrows the range and raises confidence', () {
      final none = CropAdvisor.assess(plot(), _now);
      final some = CropAdvisor.assess(
          plot(
              sprinkler: const SprinklerPlan(enabled: true),
              checks: [for (var i = 0; i < 2; i++) HealthCheck(_now.subtract(Duration(days: i)), 'Healthy', 'green')]),
          _now);
      expect(none.confidence, 'Low');
      expect(some.confidence, 'High');
      expect(some.daysToHarvestHigh - some.daysToHarvest, lessThan(none.daysToHarvestHigh - none.daysToHarvest));
    });

    test('the suggested sprinkler plan meets the crop need', () {
      for (final spec in cropSpecs) {
        final p = plot(crop: spec.name, daysAgo: (spec.daysToHarvest * 0.6).round(), area: 250);
        final plan = CropAdvisor.suggest(p, _now);
        final o = CropAdvisor.assess(p.copyWith(sprinkler: plan), _now);
        expect(o.waterRatio!, inInclusiveRange(0.95, 1.5), reason: spec.name);
        expect(plan.startHours, isNotEmpty);
      }
    });

    test('next sprinkler run is today if a start time is still ahead, else tomorrow', () {
      const plan = SprinklerPlan(enabled: true, startHours: [6, 17]);
      expect(plan.nextRun(_now), DateTime(2026, 10, 22, 17));
      expect(plan.nextRun(DateTime(2026, 10, 22, 18)), DateTime(2026, 10, 23, 6));
      expect(const SprinklerPlan().nextRun(_now), isNull);
    });

    test('plots survive a round trip through json', () {
      final p = plot(
          sprinkler: const SprinklerPlan(enabled: true, startHours: [5, 18], minutesPerRun: 30),
          checks: [HealthCheck(_now, 'Rust', 'orange')]);
      final back = CropPlot.fromJson(p.toJson());
      expect(back.crop, 'Tomato');
      expect(back.sprinkler.startHours, [5, 18]);
      expect(back.checks.single.label, 'Rust');
      expect(back.plantedOn, p.plantedOn);
    });
  });

  group('crop store and screens', () {
    const farmer = AppUser(uid: 'f1', name: 'Sipho', email: '', region: 'KZN Midlands', farmType: 'both');

    Future<void> end(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    Future<ProviderContainer> mount(WidgetTester tester, Widget child) async {
      ignoreFontOverflow();
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1206, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [currentUserProvider.overrideWithValue(farmer)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: child),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      return c;
    }

    testWidgets('add a crop from the sheet, see it tracked, then set up the sprinkler', (tester) async {
      final c = await mount(tester, const MyCropsScreen());
      expect(find.textContaining('No crops yet'), findsOneWidget);

      await tester.tap(find.text('Add a crop'));
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.textContaining('Maize'));
      await tester.tap(find.textContaining('Maize'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.widgetWithText(TextFormField, 'Plot name (optional)'), 'Top field');
      await tester.ensureVisible(find.text('1 month ago'));
      await tester.tap(find.text('1 month ago'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Start tracking'));
      await tester.tap(find.text('Start tracking'));
      await tester.pump(const Duration(seconds: 2));

      final plots = c.read(cropStoreProvider);
      expect(plots.single.crop, 'Maize');
      expect(plots.single.name, 'Top field');
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Harvest in'), findsOneWidget);

      await tester.tap(find.text('Top field').first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Plant health'), findsOneWidget);
      expect(find.text('Not scanned yet'), findsOneWidget);
      await tester.ensureVisible(find.text('Set up sprinkler'));
      await tester.tap(find.text('Set up sprinkler'));
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Let the AI suggest a plan'));
      await tester.tap(find.text('Let the AI suggest a plan'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Save plan'));
      await tester.tap(find.text('Save plan'));
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(cropStoreProvider).single.sprinkler.enabled, isTrue);
      expect(find.text('Change sprinkler plan'), findsOneWidget);
      await end(tester);
    });

    testWidgets('a scan result is recorded against the plot', (tester) async {
      final c = await mount(tester, const MyCropsScreen());
      final store = c.read(cropStoreProvider.notifier);
      final p = store.add(crop: 'Tomato', name: 'Plot A', plantedOn: DateTime.now().subtract(const Duration(days: 30)), areaM2: 80);
      store.addCheck(p.id, 'Late Blight', 'red');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Health 28'), findsNothing);
      expect(c.read(cropStoreProvider).single.checks.single.severity, 'red');
      expect(find.textContaining('Health'), findsOneWidget);
      await end(tester);
    });

    testWidgets('plots are saved per account and come back', (tester) async {
      final c = await mount(tester, const SizedBox());
      c.read(cropStoreProvider.notifier).add(crop: 'Spinach', name: '', plantedOn: DateTime.now(), areaM2: 20);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      final raw = (await SharedPreferences.getInstance()).getString('crop_plots_f1')!;
      expect(raw, startsWith('enc1:'), reason: 'saved sealed');
      expect(raw, isNot(contains('Spinach')));
      expect(await SecurePrefs.getString('crop_plots_f1'), contains('Spinach plot'));
      await end(tester);
    });

    testWidgets('Home has the crop health AI under the camera and Your herd under symptoms, recent scans first', (tester) async {
      await mount(tester, const Scaffold(body: HomeTab()));
      expect(find.text('Crop health AI: my crops'), findsOneWidget);
      expect(find.textContaining('Your herd'), findsOneWidget);
      expect(find.text('Water radar'), findsOneWidget);
      expect(find.text('Outbreaks near you'), findsNothing);
      expect(find.text('Community'), findsNothing);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Recent scans') < y('Scan a crop'), isTrue);
      expect(y('Open camera') < y('Crop health AI: my crops'), isTrue);
      await end(tester);
    });
  });
}
