import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/crops/crop_store.dart';
import 'package:nolifa_grow/farm/farm_models.dart';
import 'package:nolifa_grow/farm/farm_setup_screen.dart';
import 'package:nolifa_grow/farm/farm_store.dart';
import 'package:nolifa_grow/farm/irrigation_ai.dart';
import 'package:nolifa_grow/farm/water_ai_screen.dart';
import 'package:nolifa_grow/impact/impact_store.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:nolifa_grow/weather/weather_models.dart';
import 'package:nolifa_grow/weather/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecureBox;

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
const _user = AppUser(uid: 'f1', name: 'Sipho', email: 's@x.za', region: 'Greater Durban', farmType: 'both');

class _Weather extends WeatherService {
  final List<double> rain;
  _Weather(this.rain);
  @override
  Future<Forecast> forecastFor(String region) async => Forecast(
        region,
        [
          for (var i = 0; i < rain.length; i++)
            DayForecast(_today.add(Duration(days: i)), 14, 28, rain[i], rain[i] > 0 ? 80 : 5, 10, et0: 5),
        ],
        DateTime.now(),
      );
}

class _Valve implements ValveController {
  final String? error;
  final calls = <(String, int)>[];
  _Valve([this.error]);
  @override
  Future<String?> open(IrrigationSystem system, int minutes) async {
    calls.add((system.id, minutes));
    return error;
  }
}

void _ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

ProviderContainer _box({List<double>? rain, _Valve? valve}) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(_user),
    weatherServiceProvider.overrideWithValue(_Weather(rain ?? List.filled(7, 0.0))),
    if (valve != null) valveControllerProvider.overrideWithValue(valve),
    actualWeatherProvider.overrideWithValue(_NoActuals()),
  ]);
  addTearDown(c.dispose);
  return c;
}

class _NoActuals implements ActualWeather {
  @override
  Future<Map<DateTime, (double, double)>> lastDays(String region) async => {};
}

/// A tomato plot at the middle of its season with a drip system and a valve.
Future<({FarmStore farm, String plotId, String sysId, String tankId})> _setUp(ProviderContainer c, {String? valveUrl}) async {
  c.read(farmStoreProvider);
  c.read(cropStoreProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  final farm = c.read(farmStoreProvider.notifier);
  final plot = c.read(cropStoreProvider.notifier).add(
      crop: 'Tomato', name: 'Tomatoes', plantedOn: _today.subtract(const Duration(days: 51)), areaM2: 100);
  farm.setBasics(hectares: 2, soil: SoilType.loam);
  final tank = farm.addSource(WaterSourceKind.tank, 'Tank', capacityL: 10000, levelL: 8000);
  final sys = farm.addSystem(IrrigationKind.drip, 'Drip', 1500, sourceId: tank.id, valveUrl: valveUrl);
  farm.assign(plot.id, sys.id);
  return (farm: farm, plotId: plot.id, sysId: sys.id, tankId: tank.id);
}

void main() {
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('farm store', () {
    test('setup survives a restart and is stored sealed', () async {
      final c = _box();
      final s = await _setUp(c);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final c2 = _box();
      c2.read(farmStoreProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final f = c2.read(farmStoreProvider);
      expect(f.hectares, 2);
      expect(f.systems.single.name, 'Drip');
      expect(f.plotSystem[s.plotId], s.sysId);
      expect((await SharedPreferences.getInstance()).getString('farm_profile_f1'), startsWith('enc1:'));
    });

    test('removing a source unlinks it; removing a system unassigns its plots', () async {
      final c = _box();
      final s = await _setUp(c);
      s.farm.removeSource(s.tankId);
      expect(c.read(farmStoreProvider).systems.single.sourceId, isNull);
      s.farm.removeSystem(s.sysId);
      expect(c.read(farmStoreProvider).plotSystem, isEmpty);
    });

    test('the first prediction is kept on the plot', () async {
      final c = _box();
      final s = await _setUp(c);
      final plot = c.read(cropStoreProvider).firstWhere((p) => p.id == s.plotId);
      expect(plot.predictedOn, isNotNull);
    });

    test('logging a run takes the water out of the tank, never below zero', () async {
      final c = _box();
      final s = await _setUp(c);
      s.farm.logRun(s.plotId, 3000);
      expect(c.read(farmStoreProvider).sources.single.levelL, 5000);
      s.farm.logRun(s.plotId, 9000);
      expect(c.read(farmStoreProvider).sources.single.levelL, 0);
      expect(c.read(farmStoreProvider).runs.length, 2);
    });

    test('setting the tank level is limited to its size', () async {
      final c = _box();
      final s = await _setUp(c);
      s.farm.setTankLevel(s.tankId, 99999);
      expect(c.read(farmStoreProvider).sources.single.levelL, 10000);
    });

    test('holding off counts only what the rain did, once, never a plain delay or a watering day', () async {
      final c = _box(rain: [0, 0, 25, 0, 0, 0, 0]);
      final s = await _setUp(c);
      await c.read(forecastProvider.future);
      final plan = c.read(irrigationProvider)!.plans.single;
      final rainDay = plan.days.firstWhere((d) => d.rainMm > 0);
      expect(rainDay.action, isNot(DayAction.water));
      expect(s.farm.holdOff(s.plotId, 'Tomatoes', rainDay), isTrue);
      expect(s.farm.holdOff(s.plotId, 'Tomatoes', rainDay), isFalse, reason: 'already counted');
      final saved = c.read(impactStoreProvider).savings;
      expect(saved.length, 1);
      // 20 mm of useful rain, but the crop only uses 5.75 mm that day: the rain did 5.75 mm of work.
      expect(saved.single.litres, closeTo(rainDay.etc / 0.9 * 100, 0.01));
      expect(saved.single.litres, lessThan(rainDay.effRainMm / 0.9 * 100));
      final delay = plan.days.firstWhere((d) => d.action == DayAction.rest);
      expect(s.farm.holdOff(s.plotId, 'Tomatoes', delay), isFalse, reason: 'a delay is not a saving');
      final water = plan.days.firstWhere((d) => d.action == DayAction.water);
      expect(s.farm.holdOff(s.plotId, 'Tomatoes', water), isFalse);
      expect(c.read(impactStoreProvider).savings.length, 1);
    });
  });

  group('valve and autopilot', () {
    Future<(ProviderContainer, _Valve, String)> due({String? error, String? url = 'http://valve.local/open?m={minutes}'}) async {
      final valve = _Valve(error);
      final c = _box(valve: valve);
      final s = await _setUp(c, valveUrl: url);
      s.farm.soilCheck(s.plotId, SoilFeel.dry); // due today
      await c.read(forecastProvider.future);
      return (c, valve, s.plotId);
    }

    test('runNow opens the valve for the planned minutes and logs the run', () async {
      final (c, valve, plotId) = await due();
      final plan = c.read(irrigationProvider)!.plans.single;
      expect(plan.today.action, DayAction.water);
      final err = await c.read(farmStoreProvider.notifier).runNow(plan);
      expect(err, isNull);
      expect(valve.calls.single.$2, plan.today.minutes);
      final run = c.read(farmStoreProvider).runs.single;
      expect(run.plotId, plotId);
      expect(run.byValve, isTrue);
      expect(run.litres, plan.today.litres);
    });

    test('a valve that cannot be reached logs nothing and says why', () async {
      final (c, _, _) = await due(error: 'Could not reach the valve.');
      final err = await c.read(farmStoreProvider.notifier).runNow(c.read(irrigationProvider)!.plans.single);
      expect(err, 'Could not reach the valve.');
      expect(c.read(farmStoreProvider).runs, isEmpty);
    });

    test('nothing runs when the plan says no water', () async {
      final valve = _Valve();
      final c = _box(valve: valve);
      final s = await _setUp(c, valveUrl: 'http://v/open');
      s.farm.soilCheck(s.plotId, SoilFeel.wet);
      await c.read(forecastProvider.future);
      final err = await c.read(farmStoreProvider.notifier).runNow(c.read(irrigationProvider)!.plans.single);
      expect(err, contains('does not call for water'));
      expect(valve.calls, isEmpty);
    });

    test('autopilot only acts when switched on, in the morning, once a day', () async {
      final (c, valve, _) = await due();
      final farm = c.read(farmStoreProvider.notifier);
      final morning = DateTime(_now.year, _now.month, _now.day, 6);
      expect(await autopilotTick(c.read, now: morning), isEmpty, reason: 'off');
      farm.setAutopilot(true);
      expect(await autopilotTick(c.read, now: DateTime(_now.year, _now.month, _now.day, 14)), isEmpty, reason: 'too hot');
      expect(await autopilotTick(c.read, now: DateTime(_now.year, _now.month, _now.day, 3)), isEmpty, reason: 'too early');
      expect(await autopilotTick(c.read, now: morning), ['Tomatoes']);
      expect(await autopilotTick(c.read, now: morning), isEmpty, reason: 'already ran today');
      expect(valve.calls.length, 1);
    });

    test('autopilot skips a system without a valve link', () async {
      final valve = _Valve();
      final c = _box(valve: valve);
      final s = await _setUp(c); // no valve link
      s.farm.soilCheck(s.plotId, SoilFeel.dry);
      s.farm.setAutopilot(true);
      await c.read(forecastProvider.future);
      expect(await autopilotTick(c.read, now: DateTime(_now.year, _now.month, _now.day, 6)), isEmpty);
      expect(valve.calls, isEmpty);
    });
  });

  group('screens', () {
    Future<ProviderContainer> mount(WidgetTester t, Widget page, {List<double>? rain, _Valve? valve, bool setUp = false}) async {
      _ignoreFontOverflow();
      t.view.physicalSize = const Size(1206, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = _box(rain: rain, valve: valve);
      // Real timers are needed to wait for the sealed store, so step outside fake time.
      if (setUp) await t.runAsync(() => _setUp(c, valveUrl: valve == null ? null : 'http://v/open'));
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(theme: AppTheme.build(), home: page)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      return c;
    }

    testWidgets('the AI page asks for a crop first when there are none', (t) async {
      await mount(t, const WaterAiScreen());
      expect(find.textContaining('Add what you are growing'), findsOneWidget);
    });

    testWidgets('it tells the farmer to set up the farm, and still plans', (t) async {
      final c = await mount(t, const WaterAiScreen());
      c.read(cropStoreProvider.notifier).add(crop: 'Maize', name: 'Maize', plantedOn: _today.subtract(const Duration(days: 40)), areaM2: 2000);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Set up your farm for exact run times'), findsOneWidget);
      expect(find.text('Maize'), findsWidgets);
    });

    testWidgets('a dry soil plot shows what to apply and logging it takes the water from the tank', (t) async {
      final c = await mount(t, const WaterAiScreen(), setUp: true);
      final s = c.read(farmStoreProvider.notifier);
      s.soilCheck(c.read(cropStoreProvider).single.id, SoilFeel.dry);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('plot needs water today'), findsOneWidget);
      expect(find.textContaining('Apply'), findsWidgets);
      await t.scrollUntilVisible(find.text('I watered'), 400);
      await t.tap(find.text('I watered'));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(farmStoreProvider).runs.length, 1);
      expect(c.read(farmStoreProvider).sources.single.levelL, lessThan(8000));
      expect(find.text('Watered today'), findsOneWidget);
    });

    testWidgets('when rain is coming it says so and "I held off" is counted as water saved', (t) async {
      final c = await mount(t, const WaterAiScreen(), rain: [30, 0, 0, 0, 0, 0, 0], setUp: true);
      c.read(farmStoreProvider.notifier).soilCheck(c.read(cropStoreProvider).single.id, SoilFeel.dry);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Rain does the job'), findsOneWidget);
      await t.scrollUntilVisible(find.text('I held off today'), 400);
      await t.tap(find.text('I held off today'));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(impactStoreProvider).savings.length, 1);
      expect(find.text('Counted as water saved'), findsOneWidget);
    });

    testWidgets('autopilot is off and disabled until a valve is linked', (t) async {
      await mount(t, const WaterAiScreen(), setUp: true);
      expect(find.textContaining('Link a smart valve'), findsOneWidget);
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets('setup: farm size, soil, a tank and a system can be added', (t) async {
      final c = await mount(t, const FarmSetupScreen());
      c.read(cropStoreProvider.notifier).add(crop: 'Spinach', name: 'Spinach', plantedOn: _today, areaM2: 5000);
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.widgetWithText(TextFormField, 'Farm size in hectares'), '2');
      await t.pump(const Duration(milliseconds: 200));
      expect(c.read(farmStoreProvider).hectares, 2);
      expect(find.textContaining('0.50 ha planted of 2 ha (25%)'), findsOneWidget);
      await t.tap(find.text('Clay'));
      await t.pump(const Duration(milliseconds: 200));
      expect(c.read(farmStoreProvider).soil, SoilType.clay);

      await t.tap(find.text('Add').first);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.enterText(find.widgetWithText(TextFormField, 'Tank size in litres'), '5000');
      await t.enterText(find.widgetWithText(TextFormField, 'How much is in it now, litres'), '3000');
      await t.tap(find.text('Add source'));
      await t.pump(const Duration(milliseconds: 600));
      expect(c.read(farmStoreProvider).sources.single.levelL, 3000);

      await t.tap(find.text('Add').last);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.textContaining('Sprinklers').last);
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(find.widgetWithText(TextFormField, 'Litres an hour when one plot is on'), '2400');
      await t.ensureVisible(find.text('Add system'));
      await t.tap(find.text('Add system'));
      await t.pump(const Duration(milliseconds: 600));
      final sys = c.read(farmStoreProvider).systems.single;
      expect(sys.kind, IrrigationKind.sprinkler);
      expect(sys.flowLph, 2400);
    });

    testWidgets('a valve link that is not a web address is refused', (t) async {
      final c = await mount(t, const FarmSetupScreen());
      await t.tap(find.text('Add').last);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.enterText(find.widgetWithText(TextFormField, 'Smart valve link (optional)'), 'ftp://x');
      await t.ensureVisible(find.text('Add system'));
      await t.tap(find.text('Add system'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('must start with http'), findsOneWidget);
      expect(c.read(farmStoreProvider).systems, isEmpty);
    });

    testWidgets('plots larger than the farm are called out', (t) async {
      final c = await mount(t, const FarmSetupScreen());
      c.read(cropStoreProvider.notifier).add(crop: 'Maize', name: 'Big', plantedOn: _today, areaM2: 30000);
      c.read(farmStoreProvider.notifier).setBasics(hectares: 1);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('more than the farm'), findsOneWidget);
    });
  });
}
