import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/crops/crop_models.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:nolifa_grow/weather/weather_card.dart';
import 'package:nolifa_grow/weather/weather_models.dart';
import 'package:nolifa_grow/weather/weather_service.dart';
import 'package:nolifa_grow/weather/weather_threats.dart';
import 'package:nolifa_grow/crops/crop_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecureBox;

final _now = DateTime(2026, 10, 22, 9);

DayForecast _d(int i, {double min = 12, double max = 26, double rain = 0, int chance = 5, double wind = 12}) =>
    DayForecast(DateTime(2026, 10, 22).add(Duration(days: i)), min, max, rain, chance, wind);

Forecast _week(List<DayForecast> days) => Forecast('KZN Midlands', days, _now);

List<DayForecast> _calm() => [for (var i = 0; i < 7; i++) _d(i)];

CropPlot _plot(String crop, {String name = 'Plot', SprinklerPlan s = const SprinklerPlan()}) =>
    CropPlot(id: crop, crop: crop, name: name, plantedOn: _now.subtract(const Duration(days: 30)), areaM2: 100, sprinkler: s);

void main() {
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));

  group('threats', () {
    test('a calm week has none', () {
      expect(assessWeather(_week(_calm()), [_plot('Tomato')], _now), isEmpty);
    });

    test('frost: the first cold night, hard below 0, with the tender plots named', () {
      final days = _calm()..[2] = _d(2, min: 1.5)..[3] = _d(3, min: -1);
      final t = assessWeather(_week(days), [_plot('Tomato', name: 'North'), _plot('Spinach', name: 'South')], _now);
      final frost = t.firstWhere((x) => x.kind == 'frost');
      expect(frost.title, 'Frost risk ${dayName(DateTime(2026, 10, 24), _now)}');
      expect(frost.severity, 'orange', reason: 'the first night is only 1.5');
      expect(frost.plots, ['North'], reason: 'spinach is not frost tender');
      final hard = assessWeather(_week(_calm()..[1] = _d(1, min: -2)), [], _now).single;
      expect(hard.severity, 'red');
      expect(hard.title, 'Hard frost tomorrow');
    });

    test('heat at 35 C, urgent at 38', () {
      expect(assessWeather(_week(_calm()..[4] = _d(4, max: 36)), [_plot('Spinach')], _now).single.severity, 'orange');
      expect(assessWeather(_week(_calm()..[4] = _d(4, max: 39)), [], _now).single.severity, 'red');
      expect(assessWeather(_week(_calm()..[4] = _d(4, max: 34.9)), [], _now), isEmpty);
    });

    test('heavy rain: 30 mm in a day, or 60 over three, and it names wet-sensitive crops', () {
      final t = assessWeather(_week(_calm()..[5] = _d(5, rain: 34, chance: 90)), [_plot('Potato', name: 'P'), _plot('Maize', name: 'M')], _now);
      expect(t.single.kind, 'heavyRain');
      expect(t.single.plots, ['P']);
      final three = assessWeather(_week(_calm()..[1] = _d(1, rain: 22)..[2] = _d(2, rain: 22)..[3] = _d(3, rain: 22)), [], _now);
      expect(three.single.kind, 'heavyRain', reason: '66 mm over three days');
      expect(assessWeather(_week(_calm()..[1] = _d(1, rain: 49)), [], _now).single.severity, 'orange');
      expect(assessWeather(_week(_calm()..[1] = _d(1, rain: 50)), [], _now).single.severity, 'red');
    });

    test('a dry week needs little rain and several hot days', () {
      final hot = [for (var i = 0; i < 7; i++) _d(i, max: 31)];
      expect(assessWeather(_week(hot), [_plot('Maize')], _now).single.kind, 'drySpell');
      expect(assessWeather(_week([for (var i = 0; i < 7; i++) _d(i, max: 31, rain: 1)]), [], _now), isEmpty,
          reason: '7 mm in the week is not a dry spell');
    });

    test('strong wind', () {
      expect(assessWeather(_week(_calm()..[2] = _d(2, wind: 55)), [], _now).single.kind, 'wind');
    });

    test('urgent first, then soonest', () {
      final days = _calm()
        ..[1] = _d(1, max: 36)
        ..[3] = _d(3, min: -1)
        ..[5] = _d(5, rain: 34, chance: 90);
      final t = assessWeather(_week(days), [], _now);
      expect([for (final x in t) x.kind], ['frost', 'heat', 'heavyRain']);
    });

    test('day names: today, tomorrow, then the weekday', () {
      expect(dayName(DateTime(2026, 10, 22), _now), 'today');
      expect(dayName(DateTime(2026, 10, 23), _now), 'tomorrow');
      expect(dayName(DateTime(2026, 10, 26), _now), 'Mon 26 Oct');
    });
  });

  group('sprinkler', () {
    const on = SprinklerPlan(enabled: true, litresPerMinute: 10, minutesPerRun: 30, startHours: [6]);

    test('real rain tomorrow means skip the run, and says how much water that saves', () {
      final f = _week(_calm()..[1] = _d(1, rain: 12, chance: 80));
      final a = sprinklerAdvice(f, _plot('Tomato', s: on), _now)!;
      expect(a, contains('Skip the sprinkler run'));
      expect(a, contains('tomorrow'));
      expect(a, contains('300 litres'));
    });

    test('a shower that probably will not come does not cancel watering', () {
      expect(sprinklerAdvice(_week(_calm()..[1] = _d(1, rain: 12, chance: 30)), _plot('Tomato', s: on), _now), isNull);
      expect(sprinklerAdvice(_week(_calm()..[1] = _d(1, rain: 2, chance: 90)), _plot('Tomato', s: on), _now), isNull);
    });

    test('three hot dry days add a run; no sprinkler plan means no advice', () {
      final hot = _week([for (var i = 0; i < 7; i++) _d(i, max: 34)]);
      expect(sprinklerAdvice(hot, _plot('Tomato', s: on), _now), contains('extra run'));
      expect(sprinklerAdvice(hot, _plot('Tomato'), _now), isNull);
    });
  });

  group('forecast data', () {
    test('Open-Meteo daily json becomes a forecast', () {
      final body = jsonEncode({
        'daily': {
          'time': ['2026-10-22', '2026-10-23'],
          'temperature_2m_max': [27.5, 21],
          'temperature_2m_min': [11, 1.2],
          'precipitation_sum': [0, 14.2],
          'precipitation_probability_max': [5, 85],
          'wind_speed_10m_max': [14, 41],
        }
      });
      final f = parseOpenMeteo('Zululand', body);
      expect(f.days.length, 2);
      expect(f.days[1].minC, 1.2);
      expect(f.days[1].rainMm, 14.2);
      expect(f.days[1].rainChance, 85);
      expect(f.days[1].windKmh, 41);
      expect(f.region, 'Zululand');
    });

    test('a forecast survives a json round trip', () {
      final f = Forecast.fromJson(_week(_calm()).toJson());
      expect(f.days.length, 7);
      expect(f.region, 'KZN Midlands');
    });

    test('the demo forecast carries a frost, heat and heavy rain and says it is demo', () {
      final f = demoForecast('Zululand', _now);
      expect(f.demo, isTrue);
      expect(assessWeather(f, [], _now).map((t) => t.kind).toSet(), containsAll(['frost', 'heat', 'heavyRain']));
    });
  });

  group('service', () {
    test('no signal and nothing saved gives the demo forecast; a saved one is used when there is no signal', () async {
      SharedPreferences.setMockInitialValues({});
      final off = _Offline();
      final first = await off.forecastFor('Zululand');
      expect(first.demo, isTrue);

      final live = _Live();
      final real = await live.forecastFor('Zululand');
      expect(real.demo, isFalse);
      expect(real.saved, isFalse);

      final again = await off.forecastFor('Zululand');
      expect(again.demo, isFalse);
      expect(again.saved, isTrue, reason: 'last real forecast, marked as saved');
      expect(again.days.length, 7);
    });
  });

  group('on screen', () {
    const farmer = AppUser(uid: 'f1', name: 'Sipho', email: '', region: 'KZN Midlands', farmType: 'both');

    testWidgets('the weather card shows the week, the top threat and that it is demo', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1206, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(farmer),
        weatherServiceProvider.overrideWithValue(_Offline()),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: const Scaffold(body: SingleChildScrollView(child: WeatherCard()))),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Weather, KZN Midlands'), findsOneWidget);
      expect(find.text('Demo forecast'), findsOneWidget);
      expect(find.textContaining('Frost'), findsWidgets);
      expect(c.read(weatherThreatsProvider), isNotEmpty);
      // The threats name the farmer's own plots once they are added.
      c.read(cropStoreProvider.notifier).add(crop: 'Tomato', name: 'Top field', plantedOn: DateTime.now(), areaM2: 50);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(weatherThreatsProvider).firstWhere((t) => t.kind == 'frost').plots, ['Top field']);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _Offline extends WeatherService {
  @override
  Future<Forecast> fetch(String region, double lat, double lon) async => throw Exception('no signal');
}

class _Live extends WeatherService {
  @override
  Future<Forecast> fetch(String region, double lat, double lon) async => Forecast(region, _calm(), DateTime.now());
}
