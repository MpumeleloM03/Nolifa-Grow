import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/crops/crop_models.dart';
import 'package:nolifa_grow/farm/farm_models.dart';
import 'package:nolifa_grow/farm/irrigation_ai.dart';
import 'package:nolifa_grow/weather/weather_models.dart';

final _now = DateTime(2026, 10, 23, 7);
final _today = DateTime(2026, 10, 23);

// A tomato plot at the middle of its season, so the crop factor is 1.15.
CropPlot _tomato({double area = 100}) =>
    CropPlot(id: 'p1', crop: 'Tomato', name: 'Tomatoes', plantedOn: _today.subtract(const Duration(days: 51)), areaM2: area);

const _drip = IrrigationSystem(id: 's1', name: 'Drip', kind: IrrigationKind.drip, flowLph: 1500, sourceId: 'w1');

FarmProfile _farm({SoilType soil = SoilType.loam, List<SoilCheck> checks = const [], List<IrrigationRun> runs = const [], bool system = true}) =>
    FarmProfile(
      hectares: 2,
      soil: soil,
      systems: system ? const [_drip] : const [],
      plotSystem: system ? const {'p1': 's1'} : const {},
      soilChecks: checks,
      runs: runs,
    );

DayForecast _d(int i, {double rain = 0, double et0 = 5, double min = 14, double max = 28}) =>
    DayForecast(_today.add(Duration(days: i)), min, max, rain, rain > 0 ? 80 : 5, 10, et0: et0);

Forecast _fc(List<double> rain, {double et0 = 5, List<DayForecast> past = const [], bool demo = false}) =>
    Forecast('KZN', [for (var i = 0; i < rain.length; i++) _d(i, rain: rain[i], et0: et0)], _now, past: past, demo: demo);

PlotPlan _plan(Forecast f, {FarmProfile? farm, CropPlot? plot}) =>
    planPlot(plot: plot ?? _tomato(), farm: farm ?? _farm(), forecast: f, now: _now, latitude: -29.8);

void main() {
  group('crop water use', () {
    test('the crop factor rises, holds, and falls through the season', () {
      final c = waterSpecFor('Tomato');
      expect(kcAt(c, 0.0), 0.60);
      expect(kcAt(c, 0.6), 1.15);
      expect(kcAt(c, 1.0), closeTo(0.80, 1e-9));
      expect(kcAt(c, 0.30), closeTo(0.875, 1e-9));
      expect(kcAt(c, 0.9), closeTo(0.975, 1e-9));
    });

    test('one watering never exceeds what the crop can use in one go, and a long run reads in hours', () {
      final dry = _plan(_fc(List.filled(7, 0.0)), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.dry)]));
      final past = [for (var i = 5; i >= 1; i--) DayForecast(_today.subtract(Duration(days: i)), 14, 30, 0, 0, 10, et0: 6)];
      final veryDry = _plan(_fc(List.filled(7, 0.0), past: past));
      expect(veryDry.today.netMm, lessThanOrEqualTo(veryDry.rawMm * 1.2 + 0.001));
      expect(dry.today.netMm, lessThanOrEqualTo(dry.rawMm * 1.2 + 0.001));
      expect(durationText(25), '25 min');
      expect(durationText(120), '2 h');
      expect(durationText(504), '8 h 24 min');
    });

    test('every crop the app grows has water figures', () {
      for (final spec in cropSpecs) {
        expect(cropWater.containsKey(spec.name), isTrue, reason: spec.name);
        final c = cropWater[spec.name]!;
        expect(c.p, inInclusiveRange(0.1, 0.8));
        expect(c.kcMid, greaterThan(0.8));
      }
    });

    test('roots deepen as the crop grows, never below 15 cm', () {
      final c = waterSpecFor('Maize');
      expect(rootDepthM(c, 0), closeTo(0.35, 1e-9));
      expect(rootDepthM(c, 0.5), closeTo(1.0, 1e-9));
      expect(rootDepthM(waterSpecFor('Spinach'), 0), closeTo(0.15, 0.001) );
    });

    test('light showers do not count, heavy rain is capped', () {
      expect(effectiveRain(2), 0);
      expect(effectiveRain(10), 8);
      expect(effectiveRain(80), 32);
    });

    test('the fallback ET0 is sensible for Durban in summer and winter', () {
      final summer = estimateEt0(19, 30, -29.8, DateTime(2026, 1, 15));
      final winter = estimateEt0(8, 21, -29.8, DateTime(2026, 7, 15));
      expect(summer, inInclusiveRange(4.5, 7.5));
      expect(winter, inInclusiveRange(1.5, 3.5));
      expect(summer, greaterThan(winter));
    });
  });

  group('a dry week', () {
    test('half-used soil is watered on the third day, with the right amount and time', () {
      final p = _plan(_fc(List.filled(7, 0.0)));
      expect(p.tawMm, closeTo(84, 0.01)); // 0.7 m of loam at 120 mm per metre
      expect(p.rawMm, closeTo(33.6, 0.01)); // tomato may use 40 percent
      expect(p.kc, 1.15);
      expect(p.days[0].action, DayAction.rest);
      expect(p.days[1].action, DayAction.rest);
      final w = p.days[2];
      expect(w.action, DayAction.water);
      // 16.8 mm used at the start plus three days of 5.75 mm, held to what the crop can use in one go.
      expect(w.netMm, closeTo(34.05, 0.01));
      // 34.05 mm over 100 m2 is 3405 L in the soil; drip is 90 percent efficient.
      expect(w.litres, closeTo(3783, 5));
      // 1500 L an hour is 25 L a minute.
      expect(w.minutes, (w.litres / 25).ceil());
      // The bucket is empty after watering, then slowly drains again.
      expect(p.days[3].depletionEnd, closeTo(5.75, 0.01));
    });

    test('watering by the calendar every day would use far more', () {
      final p = _plan(_fc(List.filled(7, 0.0)));
      expect(p.weekCalendarLitres, closeTo(7 * 5.75 / 0.9 * 100, 1));
      expect(p.weekLitres, lessThan(p.weekCalendarLitres));
      // No rain, so no rain saving: spacing the watering out is only a delay.
      expect(p.weekRainWorkLitres, 0);
    });

    test('rain does the work of the days it falls on, and no more than the crop uses', () {
      final p = _plan(_fc([0, 0, 25, 0, 0, 0, 0]));
      final d = p.days[2];
      expect(d.effRainMm, 20);
      expect(d.rainWorkLitres, closeTo(5.75 / 0.9 * 100, 0.01));
      expect(p.weekRainWorkLitres, d.rainWorkLitres);
    });

    test('a sandy soil needs watering sooner than clay', () {
      final sand = _plan(_fc(List.filled(7, 0.0)), farm: _farm(soil: SoilType.sand));
      final clay = _plan(_fc(List.filled(7, 0.0)), farm: _farm(soil: SoilType.clay));
      expect(sand.nextWater!.date.isBefore(clay.nextWater!.date) || clay.nextWater == null, isTrue);
      expect(sand.tawMm, lessThan(clay.tawMm));
    });

    test('hotter weather brings the watering forward', () {
      final mild = _plan(_fc(List.filled(7, 0.0), et0: 3));
      final hot = _plan(_fc(List.filled(7, 0.0), et0: 8));
      expect(hot.nextWater!.date.isBefore(mild.nextWater?.date ?? _today.add(const Duration(days: 30))), isTrue);
    });
  });

  group('rain', () {
    test('a good rain on day two pushes the watering back and shows as a skip', () {
      final dry = _plan(_fc(List.filled(7, 0.0)));
      final wet = _plan(_fc([0, 0, 25, 0, 0, 0, 0]));
      expect(dry.nextWater!.date, _today.add(const Duration(days: 2)));
      expect(wet.days[2].action, isNot(DayAction.water));
      expect(wet.days[2].effRainMm, 20);
      expect(wet.nextWater == null || wet.nextWater!.date.isAfter(dry.nextWater!.date), isTrue);
      expect(dry.days[2].litres, greaterThan(0));
      expect(wet.days[2].litres, 0);
    });

    test('rain tomorrow holds back a watering that was due today', () {
      final p = _plan(_fc([0, 30, 0, 0, 0, 0, 0]), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.dry)]));
      expect(p.days[0].action, DayAction.rainSkip);
      expect(p.days[0].litres, 0);
    });

    test('with no rain coming, a dry soil is watered today', () {
      final p = _plan(_fc(List.filled(7, 0.0)), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.dry)]));
      expect(p.days[0].action, DayAction.water);
    });

    test('light drizzle is ignored', () {
      final a = _plan(_fc([0, 2, 0, 0, 0, 0, 0]));
      final b = _plan(_fc(List.filled(7, 0.0)));
      expect(a.nextWater!.date, b.nextWater!.date);
    });
  });

  group('what the farmer tells it', () {
    test('a wet soil check delays watering, a dry one brings it forward', () {
      final wet = _plan(_fc(List.filled(7, 0.0)), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.wet)]));
      final dry = _plan(_fc(List.filled(7, 0.0)), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.dry)]));
      expect(wet.depletionNowMm, 0);
      expect(dry.depletionNowMm, closeTo(dry.rawMm, 0.01));
      expect(wet.nextWater!.date.isAfter(dry.nextWater!.date), isTrue);
    });

    test('a watering already done today refills the soil', () {
      final done = IrrigationRun('p1', _now, 3783, byValve: false);
      final p = _plan(_fc(List.filled(7, 0.0)), farm: _farm(runs: [done]));
      // 3783 L at 90 percent over 100 m2 is 34 mm, more than the 16.8 mm that was used.
      expect(p.depletionNowMm, 0);
      expect(p.nextWater!.date.isAfter(_today.add(const Duration(days: 3))), isTrue);
    });

    test('checks on other plots are ignored', () {
      final p = _plan(_fc(List.filled(7, 0.0)), farm: _farm(checks: [SoilCheck('other', _now, SoilFeel.wet)]));
      expect(p.depletionNowMm, closeTo(16.8, 0.01));
    });

    test('past days dry the soil out', () {
      final past = [for (var i = 4; i >= 1; i--) DayForecast(_today.subtract(Duration(days: i)), 14, 28, 0, 0, 10, et0: 5)];
      final p = _plan(_fc(List.filled(7, 0.0), past: past));
      // 16.8 + four days of 5.75 mm = 39.8, clamped to what the roots can reach.
      expect(p.depletionNowMm, closeTo(39.8, 0.01));
      expect(p.today.action, DayAction.water);
    });

    test('rain over the last days refills it', () {
      final past = [
        DayForecast(_today.subtract(const Duration(days: 2)), 14, 24, 40, 90, 10, et0: 3),
        DayForecast(_today.subtract(const Duration(days: 1)), 14, 24, 0, 5, 10, et0: 3),
      ];
      final p = _plan(_fc(List.filled(7, 0.0), past: past));
      expect(p.depletionNowMm, lessThan(8));
    });
  });

  group('honesty', () {
    test('confidence is low with a demo forecast and nothing felt', () {
      final p = _plan(_fc(List.filled(7, 0.0), demo: true), farm: _farm(system: false));
      expect(p.confidenceLabel, 'Low');
      expect(p.why.any((l) => l.contains('demo forecast')), isTrue);
      expect(p.why.any((l) => l.contains('Feel the soil')), isTrue);
    });

    test('confidence is high with a real forecast, past days and a fresh soil check', () {
      final past = [DayForecast(_today.subtract(const Duration(days: 1)), 14, 28, 0, 0, 10, et0: 5)];
      final p = _plan(_fc(List.filled(7, 0.0), past: past), farm: _farm(checks: [SoilCheck('p1', _now, SoilFeel.ok)]));
      expect(p.confidenceLabel, 'High');
      expect(p.why.any((l) => l.contains('Feel the soil')), isFalse);
    });

    test('with no irrigation system it still plans, but gives no run time', () {
      final p = _plan(_fc(List.filled(7, 0.0)), farm: _farm(system: false));
      final w = p.nextWater!;
      expect(w.minutes, 0);
      expect(w.litres, greaterThan(0));
    });

    test('the plan explains itself in words', () {
      final p = _plan(_fc(List.filled(7, 0.0)));
      expect(p.why.first, contains('Tomato uses 5.8 mm today'));
      expect(p.why.any((l) => l.contains('cm of loam soil')), isTrue);
      expect(p.why.any((l) => l.contains('runs out of easy water')), isTrue);
    });
  });

  group('the whole farm', () {
    test('adds up the plots and finds what is drawn from each tank', () {
      final a = _tomato();
      final b = CropPlot(id: 'p2', crop: 'Spinach', name: 'Spinach', plantedOn: _today.subtract(const Duration(days: 20)), areaM2: 50);
      final farm = FarmProfile(
        hectares: 1,
        systems: const [_drip],
        plotSystem: const {'p1': 's1', 'p2': 's1'},
        sources: const [WaterSource(id: 'w1', name: 'Tank', kind: WaterSourceKind.tank, capacityL: 10000, levelL: 6000)],
      );
      final plan = planFarm(plots: [a, b], farm: farm, forecast: _fc(List.filled(7, 0.0)), now: _now, latitude: -29.8);
      expect(plan.plans.length, 2);
      expect(plan.weekLitres, closeTo(plan.plans[0].weekLitres + plan.plans[1].weekLitres, 0.001));
      final drawn = weekDrawFrom(farm.sources.first, farm, plan);
      expect(drawn, plan.weekLitres);
      expect(tankDays(farm.sources.first, drawn), closeTo(6000 / (drawn / 7), 0.001));
      expect(tankDays(farm.sources.first, 0), isNull);
      expect(plan.savedPct, inInclusiveRange(0.0, 1.0));
    });
  });

  group('storage', () {
    test('a farm profile survives a save and reload', () {
      final f = FarmProfile(
        hectares: 3.5,
        soil: SoilType.clay,
        sources: const [WaterSource(id: 'w', name: 'Tank', kind: WaterSourceKind.tank, capacityL: 5000, levelL: 1200)],
        systems: const [IrrigationSystem(id: 's', name: 'Drip', kind: IrrigationKind.drip, flowLph: 900, sourceId: 'w', valveUrl: 'http://192.168.1.50/relay/0')],
        plotSystem: const {'p1': 's'},
        soilChecks: [SoilCheck('p1', _now, SoilFeel.dry)],
        runs: [IrrigationRun('p1', _now, 500, byValve: true)],
        heldOff: const {'p1|2026-10-22'},
        autopilot: true,
      );
      final back = FarmProfile.fromJson(f.toJson());
      expect(back.hectares, 3.5);
      expect(back.soil, SoilType.clay);
      expect(back.systems.single.valveUrl, 'http://192.168.1.50/relay/0');
      expect(back.plotSystem['p1'], 's');
      expect(back.soilChecks.single.feel, SoilFeel.dry);
      expect(back.runs.single.byValve, isTrue);
      expect(back.heldOff, {'p1|2026-10-22'});
      expect(back.autopilot, isTrue);
      expect(back.isSetUp, isTrue);
    });

    test('a forecast keeps its past days and ET0 through a save', () {
      final f = _fc(List.filled(7, 0.0), past: [DayForecast(_today.subtract(const Duration(days: 1)), 14, 28, 1, 0, 10, et0: 4.4)]);
      final back = Forecast.fromJson(f.toJson());
      expect(back.past.single.et0, 4.4);
      expect(back.days.first.et0, 5);
    });
  });
}
