import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  // A saved copy of the real DWS KwaZulu-Natal page for 19 October 2026.
  final html = File('test/fixtures/dws_kn.html').readAsStringSync();

  group('reading the DWS page', () {
    test('gets the date and every dam with its levels', () {
      final r = parseDwsProvince(html);
      expect(r.date, DateTime(2026, 10, 19));
      expect(r.dams.length, 19);
      final midmar = r.dams.firstWhere((d) => d.name == 'Midmar Dam');
      expect(midmar.river, 'Mgeni River');
      expect(midmar.fsc, 235.5);
      expect(midmar.thisWeek, 89.5);
      expect(midmar.lastWeek, 90.6);
      expect(midmar.lastYear, 94.3);
      expect(r.dams.map((d) => d.name), containsAll(['Inanda Dam', 'Hazelmere Dam', 'Pongolapoort Dam']));
    });

    test('a page that is not the report is refused, not guessed', () {
      expect(() => parseDwsProvince('<html>Invalid Province</html>'), throwsFormatException);
      expect(() => parseDwsProvince('<title>State of Dams on 2026-10-19</title>'), throwsFormatException);
    });

    test('a report survives a json round trip', () {
      final r = DwsReport.fromJson(parseDwsProvince(html).toJson());
      expect(r.dams.length, 19);
      expect(r.date, DateTime(2026, 10, 19));
    });
  });

  group('system levels', () {
    test('Greater Durban is the capacity-weighted level of its four dams', () {
      final dams = parseDwsProvince(html).dams;
      final sys = supplySystems['Greater Durban']!;
      final now = systemLevel(sys, dams, (d) => d.thisWeek);
      // Inanda 237.5 @ 99.3, Nagle 23.3 @ 91.7, Midmar 235.5 @ 89.5, Albert Falls 285.7 @ 84.9
      final expected = (237.5 * 99.3 + 23.3 * 91.7 + 235.5 * 89.5 + 285.7 * 84.9) / (237.5 + 23.3 + 235.5 + 285.7);
      expect(now, closeTo(expected, 0.001));
      expect(now, inInclusiveRange(80, 100));
    });

    test('every system maps to dams that are really on the page', () {
      final names = parseDwsProvince(html).dams.map((d) => d.name).toSet();
      for (final s in supplySystems.values) {
        expect(names.containsAll(s.dams), isTrue, reason: s.name);
      }
    });

    test('a system with no matching dam has no level', () {
      expect(systemLevel(const SupplySystem('x', 'X', 'P', ['Nope Dam']), parseDwsProvince(html).dams, (d) => d.thisWeek).isNaN, isTrue);
    });
  });

  group('forecast from weekly readings', () {
    final date = DateTime(2026, 10, 19);

    test('a slow fall projects forward and says what it used', () {
      final f = forecastFromWeekly(thisWeek: 87.9, lastWeek: 88.2, reportDate: date);
      expect(f.changePerDay, closeTo(-0.043, 0.001));
      expect(f.days.length, 7);
      expect(f.days.last, closeTo(87.9 - 0.043 * 7, 0.01));
      expect(f.daysToLow, isNull, reason: 'a 0.04 point fall is steady, not a countdown');
      expect(f.confidence, lessThan(0.5), reason: 'two weekly points is thin evidence');
      expect(f.why, contains('DWS'));
      expect(f.why, contains('Weekly readings only'));
    });

    test('a fast fall gives days to Low and to Critical', () {
      final f = forecastFromWeekly(thisWeek: 45, lastWeek: 52, reportDate: date); // -1 a day
      expect(f.changePerDay, closeTo(-1, 0.001));
      expect(f.daysToLow, closeTo(5, 0.01));
      expect(f.daysToCritical, closeTo(25, 0.01));
    });

    test('heavy rain slows a fall, and very heavy rain turns it around', () {
      const dry = RainOutlook(5, 0, 0);
      final base = forecastFromWeekly(thisWeek: 45, lastWeek: 52, reportDate: date, rain: dry);
      final wet = forecastFromWeekly(thisWeek: 45, lastWeek: 52, reportDate: date, rain: const RainOutlook(5, 30, 0));
      final flood = forecastFromWeekly(thisWeek: 45, lastWeek: 52, reportDate: date, rain: const RainOutlook(5, 60, 0));
      expect(wet.changePerDay, closeTo(-0.5, 0.001));
      expect(wet.changePerDay, greaterThan(base.changePerDay));
      expect(flood.changePerDay, greaterThan(0));
      expect(flood.why, contains('heavy rain'));
    });

    test('a hot dry week speeds a fall', () {
      final f = forecastFromWeekly(thisWeek: 45, lastWeek: 52, reportDate: date, rain: const RainOutlook(5, 1, 4));
      expect(f.changePerDay, closeTo(-1.3, 0.001));
      expect(f.why, contains('hot and dry'));
    });
  });

  group('the store in live mode', () {
    test('real dam levels appear as communities with a source, next to anything a provider published', () async {
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u'),
        marketNameProvider.overrideWithValue('U'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        waterFeedProvider.overrideWithValue(_FixtureFeed(html)),
      ]);
      addTearDown(c.dispose);
      c.listen(marketProvider, (_, __) {});
      c.listen(waterProvider, (_, __) {});
      c.read(marketProvider.notifier).setDemoMode(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final s = c.read(waterProvider);
      expect(s.demo, isFalse);
      expect(s.zones.map((z) => z.name), containsAll(['Greater Durban', 'KZN Midlands', 'Zululand']));
      final durban = s.zones.firstWhere((z) => z.name == 'Greater Durban');
      expect(durban.source, contains('DWS'));
      expect(durban.readings.length, 2);
      expect(durban.level, inInclusiveRange(80, 100));
      expect(s.forecastOf(durban.id)!.why, contains('DWS'));
      expect(durban.status, WaterStatus.healthy, reason: 'the real Umgeni system is healthy right now');
    });

    test('demo mode never touches the real feed', () async {
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u'),
        marketNameProvider.overrideWithValue('U'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        waterFeedProvider.overrideWithValue(_ThrowingFeed()),
      ]);
      addTearDown(c.dispose);
      c.listen(marketProvider, (_, __) {});
      c.listen(waterProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.read(waterProvider).zones.length, 5, reason: 'the five demo communities');
      expect(c.read(waterProvider).zones.every((z) => z.source == null), isTrue);
    });
  });
}

class _FixtureFeed implements WaterFeed {
  final String html;
  _FixtureFeed(this.html);
  @override
  Future<List<FeedZone>> load() async {
    final r = parseDwsProvince(html);
    return [
      for (final s in supplySystems.values)
        if (!systemLevel(s, r.dams, (d) => d.thisWeek).isNaN)
          FeedZone(
            WaterZone(
              id: s.id,
              name: s.name,
              provider: s.provider,
              reservoir: s.dams.join(', '),
              population: 0,
              voteThreshold: 50,
              readings: [
                WaterReading(r.date.subtract(const Duration(days: 7)), systemLevel(s, r.dams, (d) => d.lastWeek)),
                WaterReading(r.date, systemLevel(s, r.dams, (d) => d.thisWeek)),
              ],
              source: 'DWS weekly State of Dams, 2026-10-19',
            ),
            forecastFromWeekly(
                thisWeek: systemLevel(s, r.dams, (d) => d.thisWeek),
                lastWeek: systemLevel(s, r.dams, (d) => d.lastWeek),
                reportDate: r.date),
          )
    ];
  }
}

class _ThrowingFeed implements WaterFeed {
  @override
  Future<List<FeedZone>> load() async => throw StateError('the demo must not read the real feed');
}
