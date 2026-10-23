import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/impact/impact_models.dart';
import 'package:nolifa_grow/impact/impact_screen.dart';
import 'package:nolifa_grow/impact/impact_store.dart';
import 'package:nolifa_grow/weather/weather_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecureBox;

class _Actuals implements ActualWeather {
  final Map<DateTime, (double, double)> days;
  _Actuals(this.days);
  @override
  Future<Map<DateTime, (double, double)>> lastDays(String region) async => days;
}

final _now = DateTime(2026, 10, 22, 9);
final _today = DateTime(2026, 10, 22);

ProviderContainer _box([Map<DateTime, (double, double)> actuals = const {}]) => ProviderContainer(
    overrides: [actualWeatherProvider.overrideWithValue(_Actuals(actuals))]);

void main() {
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Wilson interval', () {
    test('8 of 10 is wide, 800 of 1000 is tight', () {
      final (lo, hi) = wilson(8, 10);
      expect(lo, closeTo(0.490, 0.005));
      expect(hi, closeTo(0.943, 0.005));
      final (lo2, hi2) = wilson(800, 1000);
      expect(hi2 - lo2, lessThan(0.06));
    });
    test('no cases means no information', () => expect(wilson(0, 0), (0.0, 1.0)));
    test('all right still leaves doubt', () => expect(wilson(5, 5).$1, lessThan(0.6)));
  });

  group('summary', () {
    ScanFeedback s(int i, Verdict v, double conf) =>
        ScanFeedback('$i', _now, 'crop', 'x', 'X', conf, v);

    test('unsure answers are left out of accuracy and counted apart', () {
      final d = ImpactData(scans: [
        s(1, Verdict.right, 90),
        s(2, Verdict.right, 85),
        s(3, Verdict.wrong, 60),
        s(4, Verdict.unsure, 70),
      ]);
      final x = ImpactSummary.of(d);
      expect(x.scanAccuracy.n, 3);
      expect(x.scanAccuracy.hits, 2);
      expect(x.unsure, 1);
      expect(x.highConfidence.value, 1.0);
      expect(x.lowConfidence.value, 0.0);
      expect(x.scanAccuracy.claimable, isFalse);
    });

    test('30 answers can be claimed', () {
      final d = ImpactData(scans: [for (var i = 0; i < 30; i++) s(i, Verdict.right, 90)]);
      expect(ImpactSummary.of(d).scanAccuracy.claimable, isTrue);
    });

    test('forecast rain calls and heat miss are worked out from settled days only', () {
      final d = ImpactData(forecasts: [
        ForecastPair(_today, _now, 0, 25, actualRainMm: 0, actualMaxC: 27),
        ForecastPair(_today, _now, 8, 22, actualRainMm: 0.2, actualMaxC: 22),
        ForecastPair(_today, _now, 0, 30), // not settled yet
      ]);
      final x = ImpactSummary.of(d);
      expect(x.forecastDays, 2);
      expect(x.forecastPending, 1);
      expect(x.rainCalls.hits, 1);
      expect(x.tempMae, closeTo(1.0, 0.001));
    });

    test('harvest error is signed and absolute', () {
      final d = ImpactData(harvests: [
        HarvestLog(_now, 'A', 'Tomato', _today, _today.add(const Duration(days: 4))),
        HarvestLog(_now, 'B', 'Spinach', _today, _today.subtract(const Duration(days: 2))),
      ]);
      final x = ImpactSummary.of(d);
      expect(x.harvestMaeDays, 3.0);
      expect(x.harvestBiasDays, 1.0);
      expect(x.harvestWithin3, 1);
    });

    test('water saved adds up', () {
      final d = ImpactData(savings: [WaterSaving(_now, 'A', 300, 'rain'), WaterSaving(_now, 'A', 450, 'wet soil')]);
      expect(ImpactSummary.of(d).litresSaved, 750);
    });

    test('CSV quotes and lists every event', () {
      final d = ImpactData(
        scans: [ScanFeedback('1', _now, 'crop', 'x', 'Leaf "blight"', 91, Verdict.right)],
        savings: [WaterSaving(_now, 'North', 420, 'Rain')],
      );
      final csv = impactCsv(d);
      expect(csv.split('\n').length, 3);
      expect(csv, contains('"Leaf ""blight"""'));
      expect(csv, contains('"water_saved"'));
    });
  });

  group('store', () {
    test('a verdict is replaced, not duplicated, and survives a restart', () async {
      final a = _box();
      final s = a.read(impactStoreProvider.notifier);
      s.rateScan(ScanFeedback('1', _now, 'crop', 'x', 'X', 80, Verdict.unsure));
      s.rateScan(ScanFeedback('1', _now, 'crop', 'x', 'X', 80, Verdict.right));
      expect(a.read(impactStoreProvider).scans.length, 1);
      expect(s.verdictFor('1')!.verdict, Verdict.right);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      a.dispose();

      final b = _box();
      b.read(impactStoreProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.read(impactStoreProvider).scans.single.verdict, Verdict.right);
      final raw = (await SharedPreferences.getInstance()).getString('impact_guest');
      expect(raw, startsWith('enc1:'));
    });

    Forecast f(DateTime made, double rain) => Forecast(
          'KZN',
          [for (var i = 0; i < 3; i++) DayForecast(_today.add(Duration(days: i)), 10, 25, rain, 10, 10)],
          made,
        );

    test('only future days are kept, and demo or saved forecasts are ignored', () {
      final c = _box();
      final s = c.read(impactStoreProvider.notifier);
      s.recordForecast(f(_now, 0), _now);
      expect(c.read(impactStoreProvider).forecasts.length, 2);
      s.recordForecast(Forecast('KZN', f(_now, 0).days, _now, demo: true), _now);
      s.recordForecast(Forecast('KZN', f(_now, 0).days, _now, saved: true), _now);
      expect(c.read(impactStoreProvider).forecasts.length, 2);
    });

    test('the last forecast before the day is the one judged', () async {
      final c = _box({
        _today.add(const Duration(days: 1)): (0.0, 24.0),
        _today.add(const Duration(days: 2)): (5.0, 26.0),
      });
      final s = c.read(impactStoreProvider.notifier);
      s.recordForecast(f(_now, 0), _now);
      s.recordForecast(f(_now.add(const Duration(hours: 20)), 6), _now.add(const Duration(hours: 20)));
      expect(c.read(impactStoreProvider).forecasts.first.predRainMm, 6);
      // Two days on, both days have passed.
      final later = _now.add(const Duration(days: 3));
      final n = await s.settleForecasts('KZN', later);
      expect(n, 2);
      final done = c.read(impactStoreProvider).forecasts.where((p) => p.settled).toList();
      expect(done.length, 2);
      expect(ImpactSummary.of(c.read(impactStoreProvider)).rainCalls.hits, 2);
    });

    test('being offline settles nothing and does not crash', () async {
      final c = ProviderContainer(overrides: [actualWeatherProvider.overrideWithValue(_Throwing())]);
      final s = c.read(impactStoreProvider.notifier);
      s.recordForecast(f(_now, 0), _now);
      expect(await s.settleForecasts('KZN', _now.add(const Duration(days: 3))), 0);
    });
  });

  group('screen', () {
    testWidgets('an empty ledger explains how to start, sample data is labelled', (t) async {
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [actualWeatherProvider.overrideWithValue(_Actuals(const {}))],
        child: const MaterialApp(home: ImpactScreen()),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('No answers yet'), findsOneWidget);
      expect(find.textContaining('SAMPLE DATA'), findsNothing);
      await t.ensureVisible(find.text('Show a labelled sample'));
      await t.tap(find.text('Show a labelled sample'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('SAMPLE DATA'), findsOneWidget);
      expect(find.textContaining('agreed with you'), findsOneWidget);
    });

    testWidgets('feedback buttons write a verdict', (t) async {
      late ProviderContainer c;
      await t.pumpWidget(ProviderScope(
        child: Consumer(builder: (ctx, ref, _) {
          c = ProviderScope.containerOf(ctx);
          return const MaterialApp(
              home: Scaffold(
                  body: FeedbackBar(id: 'z', kind: 'crop', label: 'Tomato_Late_blight', plainName: 'Late blight', confidence: '91.5')));
        }),
      ));
      await t.tap(find.text('No, wrong'));
      await t.pump();
      final v = c.read(impactStoreProvider).scans.single;
      expect(v.verdict, Verdict.wrong);
      expect(v.confidence, 91.5);
      expect(find.text('Saved. Thank you.'), findsOneWidget);
    });
  });
}

class _Throwing implements ActualWeather {
  @override
  Future<Map<DateTime, (double, double)>> lastDays(String region) async => throw Exception('offline');
}
