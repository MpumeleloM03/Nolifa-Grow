import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

class _Wx implements LiveWeather {
  final List<WxDay> days;
  _Wx(this.days);
  @override
  Future<List<WxDay>> forecast(double lat, double lng) async => days;
}

final _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
WxDay _d(int i, {double min = 12, double max = 26, double rain = 0, double wind = 12}) =>
    WxDay(_today.add(Duration(days: i)), min, max, rain, wind);

ProviderContainer _box({
  bool live = true,
  (double, double)? at = (-29.97, 30.89), // Umlazi
  List<WxDay>? wx,
}) {
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue('u'),
    marketNameProvider.overrideWithValue('u'),
    marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
    waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
    roadRepositoryProvider.overrideWithValue(LocalRoadRepository.memory(seeds: false)),
    marketStartsLiveProvider.overrideWithValue(live),
    userLocationProvider.overrideWith((ref) async => at),
    liveWeatherProvider.overrideWithValue(_Wx(wx ?? [_d(0), _d(1), _d(2)])),
    waterFeedProvider.overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  c.listen(marketProvider, (_, __) {});
  c.listen(waterProvider, (_, __) {});
  c.listen(roadProvider, (_, __) {});
  return c;
}

void main() {
  group('real weather warnings', () {
    test('ordinary weather says nothing', () {
      expect(weatherAlertsFor([_d(0), _d(1)], 'Umlazi', _today), isEmpty);
    });

    test('frost, heat, heavy rain and wind each give a warning with the right size', () {
      final a = weatherAlertsFor([
        _d(0, min: 1),
        _d(1, min: -2),
        _d(2, max: 37),
        _d(3, rain: 45),
        _d(4, rain: 80),
        _d(5, wind: 62),
      ], 'Umlazi', _today);
      final byTitle = {for (final x in a) x.title: x};
      expect(byTitle['Frost risk today']!.severity, 1);
      expect(byTitle['Hard frost tomorrow']!.severity, 2);
      expect(byTitle['Very hot in 2 days'], isNotNull);
      expect(byTitle['Heavy rain in 3 days']!.severity, 1);
      expect(byTitle['Heavy rain in 4 days']!.severity, 2);
      expect(byTitle['Strong wind in 5 days'], isNotNull);
      expect(a.every((x) => x.trust == 'Open-Meteo forecast' && x.area == 'Umlazi'), isTrue);
    });
  });

  group('where the user really is', () {
    test('the nearest supply system comes from the position', () {
      expect(nearestSystem(-29.97, 30.89)!.name, 'Greater Durban');
      expect(nearestSystem(-29.60, 30.38)!.name, 'KZN Midlands'); // Pietermaritzburg
      expect(nearestSystem(-28.78, 32.04)!.name, 'Zululand'); // Richards Bay
      expect(nearestSystem(-27.76, 29.93)!.name, 'Northern KZN'); // Newcastle
    });

    test('a place outside KwaZulu-Natal has no real dam data', () {
      expect(nearestSystem(-26.2, 28.05), isNull); // Johannesburg
      expect(nearestSystem(-33.92, 18.42), isNull); // Cape Town
    });

    test('the water page puts the user in their own supply system', () async {
      final c = _box(at: (-29.60, 30.38));
      await c.read(userLocationProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(waterProvider).locationZoneId, 'dws-midlands');
      expect(c.read(waterProvider).outsideCoverage, isFalse);
    });

    test('outside the area it says so', () async {
      final c = _box(at: (-26.2, 28.05));
      await c.read(userLocationProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(waterProvider).outsideCoverage, isTrue);
    });
  });

  group('alerts in the shipped apps', () {
    test('live mode shows no made-up alerts, outbreaks, farms or orders', () async {
      final c = _box();
      await c.read(weatherAlertsProvider.future);
      final s = c.read(marketProvider);
      expect(s.demoMode, isFalse);
      expect(s.alerts, isEmpty);
      expect(s.cases, isEmpty);
      expect(s.orders, isEmpty);
      expect(s.products, isEmpty);
      expect(c.read(allAlertsProvider), isEmpty);
    });

    test('live alerts are the real weather where the user is', () async {
      final c = _box(wx: [_d(0, min: -1), _d(1)]);
      await c.read(weatherAlertsProvider.future);
      final a = c.read(allAlertsProvider);
      expect(a.single.title, 'Hard frost today');
      expect(a.single.kind, AlertKind.weather);
    });

    test('with location off there are no weather warnings and nothing is guessed', () async {
      final c = _box(at: null, wx: [_d(0, min: -5)]);
      await c.read(weatherAlertsProvider.future);
      expect(c.read(allAlertsProvider), isEmpty);
    });

    test('road warnings from drivers within 15 km show up, further ones do not', () async {
      final c = _box();
      final repo = c.read(roadRepositoryProvider);
      final now = DateTime.now();
      RoadHazard h(String id, double lat, double lng) => RoadHazard(
          id: id, kind: HazardKind.flooding, lat: lat, lng: lng, reportedAt: now, lastSeen: now, reporter: 'r', confirms: const ['r']);
      await repo.save(h('near', -29.95, 30.90));
      await repo.save(h('far', -29.60, 30.38));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await c.read(userLocationProvider.future);
      final a = c.read(roadAlertsProvider);
      expect(a.length, 1);
      expect(a.single.id, 'road-near');
      expect(a.single.severity, 2);
    });

    test('demo mode still has its story for tests and presentations', () {
      final c = _box(live: false);
      expect(c.read(marketProvider).demoMode, isTrue);
      expect(c.read(allAlertsProvider), isNotEmpty);
    });

    test('the demo switch does nothing in the shipped apps', () {
      final c = _box();
      c.read(marketProvider.notifier).setDemoMode(true);
      expect(c.read(marketProvider).demoMode, isFalse);
    });
  });
}
