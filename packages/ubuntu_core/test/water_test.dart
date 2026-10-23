import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

List<WaterReading> series(double start, double perDay, {int n = 28, double wobble = 0}) {
  final now = DateTime(2026, 10, 21, 12);
  final perStep = perDay / 4; // four readings a day
  return [
    for (var i = 0; i < n; i++)
      WaterReading(now.subtract(Duration(hours: 6 * (n - 1 - i))),
          start + perStep * i + (i.isEven ? wobble : -wobble)),
  ];
}

WaterZone zone(double level, {int threshold = 3, String id = 'z1'}) => WaterZone(
      id: id,
      name: 'Testville',
      provider: 'Test Water',
      reservoir: 'Test Reservoir',
      population: 1000,
      voteThreshold: threshold,
      readings: [WaterReading(DateTime(2026, 10, 21), level)],
    );

void main() {
  group('status', () {
    test('levels map to Healthy, Watch, Low and Critical', () {
      expect(WaterStatusX.of(80), WaterStatus.healthy);
      expect(WaterStatusX.of(60), WaterStatus.healthy);
      expect(WaterStatusX.of(59.9), WaterStatus.watch);
      expect(WaterStatusX.of(40), WaterStatus.watch);
      expect(WaterStatusX.of(39.9), WaterStatus.low);
      expect(WaterStatusX.of(20), WaterStatus.low);
      expect(WaterStatusX.of(19.9), WaterStatus.critical);
    });

    test('only Low and Critical communities can ask for help', () {
      expect(WaterStatus.healthy.canRequestHelp, isFalse);
      expect(WaterStatus.watch.canRequestHelp, isFalse);
      expect(WaterStatus.low.canRequestHelp, isTrue);
      expect(WaterStatus.critical.canRequestHelp, isTrue);
    });
  });

  group('forecast', () {
    test('a steady fall is projected forward', () {
      // 70% falling 3 points a day for a week.
      final f = forecastWater(series(70, -3));
      expect(f.changePerDay, closeTo(-3, 0.4));
      final last = series(70, -3).last.level;
      expect(f.daysToCritical, closeTo((last - 20) / 3, 0.6));
      expect(f.daysToEmpty, closeTo(last / 3, 0.8));
      expect(f.days.first, lessThan(last));
      expect(f.days.length, 7);
      expect(f.why, contains('Falling'));
      expect(f.confidence, greaterThan(0.6));
    });

    test('noise lowers confidence but not the direction', () {
      final clean = forecastWater(series(70, -3));
      final noisy = forecastWater(series(70, -3, wobble: 2));
      expect(noisy.changePerDay, lessThan(-1.5));
      expect(noisy.confidence, lessThan(clean.confidence));
    });

    test('a steady or recovering supply has no countdown', () {
      expect(forecastWater(series(65, 0)).daysToCritical, isNull);
      final up = forecastWater(series(40, 2));
      expect(up.daysToLow, isNull);
      expect(up.why, contains('Recovering'));
    });

    test('already below a line means zero days to it', () {
      final f = forecastWater(series(35, -2));
      expect(f.daysToLow, 0);
      expect(f.daysToCritical, isNotNull);
    });

    test('too few readings gives no forecast, honestly', () {
      final f = forecastWater(series(50, -3, n: 3));
      expect(f.confidence, 0);
      expect(f.daysToCritical, isNull);
      expect(f.why, contains('Not enough'));
    });

    test('known demand speeds the fall; rain slows it', () {
      final base = forecastWater(series(70, -3));
      expect(forecastWater(series(70, -3), demand: 0.3).changePerDay, lessThan(base.changePerDay));
      expect(forecastWater(series(70, -3), rain: 0.3).changePerDay, greaterThan(base.changePerDay));
    });

    test('forecast levels stay between 0 and 100', () {
      final f = forecastWater(series(30, -6), horizonDays: 10);
      expect(f.days.every((d) => d >= 0 && d <= 100), isTrue);
      expect(f.days.last, 0);
    });
  });

  group('preparing for the worst case', () {
    test('litres, days of cover and bottles to close the gap', () {
      final f = forecastWater(series(45, -3));
      const prefs = WaterPrefs(household: 4, tankLitres: 500, herd: 0);
      final plan = planWater(prefs: prefs, forecast: f);
      expect(plan.litresPerDay, 60); // 4 people x 15 L
      expect(plan.daysOfCover, closeTo(500 / 60, 0.01));
      expect(plan.daysToCover, greaterThanOrEqualTo(3));
      expect(plan.shortfallLitres, (plan.litresPerDay * plan.daysToCover - 500).clamp(0, 1 << 30));
      expect(plan.bottles, (plan.shortfallLitres / 25).ceil());
    });

    test('livestock water is counted', () {
      final f = forecastWater(series(70, 0));
      final plan = planWater(prefs: const WaterPrefs(household: 2, herd: 10), forecast: f);
      expect(plan.litresPerDay, 2 * 15 + 10 * 50);
    });

    test('a full tank means no shortfall', () {
      final f = forecastWater(series(70, 0));
      final plan = planWater(prefs: const WaterPrefs(household: 2, tankLitres: 5000), forecast: f);
      expect(plan.shortfallLitres, 0);
      expect(plan.bottles, 0);
    });
  });

  // The same rules must hold on the device and on the shared backend.
  for (final make in <(String, WaterRepository Function())>[
    ('local', () => LocalWaterRepository.memory()),
    ('firestore', () => FirestoreWaterRepository(db: FakeFirebaseFirestore())),
  ]) {
    group('voting rules (${make.$1})', () {
      late WaterRepository repo;
      setUp(() => repo = make.$2());

      Future<WaterIncident?> incident(String zoneId) async =>
          activeIncidentFor(await repo.watchIncidents().first, zoneId);

      test('a healthy community cannot start a request', () async {
        expect(await repo.vote(zone(70), 'a'), VoteResult.notEligible);
        expect(await incident('z1'), isNull);
      });

      test('the first vote opens an incident; each person counts once', () async {
        final z = zone(30);
        expect(await repo.vote(z, 'a'), VoteResult.counted);
        expect(await repo.vote(z, 'a'), VoteResult.alreadyVoted);
        final i = (await incident('z1'))!;
        expect(i.votes, 1);
        expect(i.stage, IncidentStage.open);
        expect(i.threshold, 3);
        expect(await repo.hasVoted(i.id, 'a'), isTrue);
        expect(await repo.hasVoted(i.id, 'b'), isFalse);
      });

      test('enough different people send the request to the provider', () async {
        final z = zone(30);
        await repo.vote(z, 'a');
        await repo.vote(z, 'b');
        expect((await incident('z1'))!.stage, IncidentStage.open);
        await repo.vote(z, 'c');
        final i = (await incident('z1'))!;
        expect(i.votes, 3);
        expect(i.stage, IncidentStage.requested);
        expect(i.requestedAt, isNotNull);
        // Extra voices after that still count, and do not reopen anything.
        await repo.vote(z, 'd');
        expect((await incident('z1'))!.votes, 4);
        expect((await incident('z1'))!.stage, IncidentStage.requested);
      });

      test('the provider acknowledges, dispatches trucks, then resolves', () async {
        final z = zone(30, threshold: 1);
        await repo.vote(z, 'a');
        final id = (await incident('z1'))!.id;
        expect((await incident('z1'))!.stage, IncidentStage.requested);

        await repo.resolve(id); // too early: nothing happens
        expect((await incident('z1'))!.stage, IncidentStage.requested);

        await repo.acknowledge(id);
        expect((await incident('z1'))!.stage, IncidentStage.acknowledged);

        await repo.dispatch(id, trucks: 3, etaMinutes: 90, note: 'Tankers');
        final d = (await incident('z1'))!;
        expect(d.stage, IncidentStage.dispatched);
        expect(d.trucks, 3);
        expect(d.etaMinutes, 90);
        expect(d.note, 'Tankers');

        await repo.resolve(id);
        expect(await incident('z1'), isNull); // no longer active
        final all = await repo.watchIncidents().first;
        expect(all.single.stage, IncidentStage.resolved);
        expect(all.single.resolvedAt, isNotNull);
      });

      test('after a request is resolved, the next shortage is a new incident', () async {
        final z = zone(30, threshold: 1);
        await repo.vote(z, 'a');
        final first = (await incident('z1'))!;
        await repo.dispatch(first.id, trucks: 1, etaMinutes: 30);
        await repo.resolve(first.id);
        // The same person can speak up again about a new shortage.
        expect(await repo.vote(z, 'a'), VoteResult.counted);
        final second = (await incident('z1'))!;
        expect(second.epoch, first.epoch + 1);
        expect(second.id, isNot(first.id));
      });

      test('different communities do not share votes', () async {
        await repo.vote(zone(30, id: 'a-town'), 'x');
        await repo.vote(zone(30, id: 'b-town'), 'x');
        expect((await incident('a-town'))!.votes, 1);
        expect((await incident('b-town'))!.votes, 1);
      });

      test('provider readings add to a community\'s history', () async {
        await repo.upsertZone(WaterZone(
            id: 'z9',
            name: 'Nine',
            provider: 'P',
            reservoir: 'R',
            population: 10,
            voteThreshold: 2,
            readings: series(60, -1)));
        await repo.publishReading('z9', 41.5);
        final z = (await repo.watchZones().first).firstWhere((z) => z.id == 'z9');
        expect(z.level, 41.5);
        expect(z.readings.length, 29);
      });

      test('personal water details are stored per person', () async {
        await repo.savePrefs('u1', const WaterPrefs(zoneId: 'z1', household: 6, tankLitres: 2000, herd: 3));
        final p = (await repo.loadPrefs('u1'))!;
        expect([p.zoneId, p.household, p.tankLitres, p.herd], ['z1', 6, 2000, 3]);
        expect(await repo.loadPrefs('u2'), isNull);
      });
    });
  }

  group('only verified people can vote on water', () {
    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('me'),
        marketNameProvider.overrideWithValue('Me'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
      ]);
      c.listen(waterProvider, (_, __) {});
      c.listen(marketProvider, (_, __) {});
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('an unverified account is turned away and nothing is counted', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      expect(c.read(marketProvider).isVerifiedMember, isFalse);
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.notVerified);
      expect(c.read(waterProvider).incidentOf('umlazi'), isNull);
    });

    testWidgets('a verified phone can vote, once, and changing the number removes the right', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      c.read(marketProvider.notifier).verifyPhone('0821234567');
      expect(c.read(marketProvider).isVerifiedMember, isTrue);
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.counted);
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.alreadyVoted);
      // A different number is not the verified one.
      final m = c.read(marketProvider.notifier);
      m.updateProfile(c.read(marketProvider).profile.copyWith(phone: '0839999999'));
      expect(c.read(marketProvider).profile.phoneVerified, isFalse);
      expect(c.read(marketProvider).isVerifiedMember, isFalse);
      await t.pump(const Duration(seconds: 40));
    });

    testWidgets('a verified farm can vote without a phone check', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      for (final step in farmerSteps) {
        c.read(marketProvider.notifier).completeKyc(KycRole.farmer, step.id);
      }
      expect(c.read(marketProvider).isVerifiedMember, isTrue);
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.counted);
      await t.pump(const Duration(seconds: 40));
    });
  });

  group('the water store in demo mode', () {
    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('me'),
        marketNameProvider.overrideWithValue('Me'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        requireVerifiedVotesProvider.overrideWithValue(false),
      ]);
      c.listen(waterProvider, (_, __) {});
      c.listen(marketProvider, (_, __) {});
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('five communities, with the home one low and falling', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final s = c.read(waterProvider);
      expect(s.zones.length, 5);
      expect(s.myZone!.id, 'umlazi');
      expect(s.myZone!.status, WaterStatus.low);
      expect(s.forecastOf('umlazi')!.falling, isTrue);
      expect(s.forecastOf('chatsworth')!.falling, isFalse);
      expect(c.read(waterProvider.notifier).isProvider, isTrue);
    });

    testWidgets('a low community gets an alert; a healthy one does not', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final alerts = c.read(waterAlertsProvider);
      expect(alerts.single.title, contains('Umlazi'));
      expect(alerts.single.id, 'w-umlazi');
      expect(c.read(allAlertsProvider).first.id, 'w-umlazi');

      c.read(waterProvider.notifier).selectZone('chatsworth');
      await t.pump(const Duration(milliseconds: 100));
      expect(c.read(waterAlertsProvider), isEmpty);
    });

    testWidgets('voting, neighbours, provider response and trucks, end to end', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final store = c.read(waterProvider.notifier);

      expect(await store.vote(), VoteResult.counted);
      var i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.votes, 1);
      expect(c.read(waterProvider).votedIn(i), isTrue);
      expect(await store.vote(), VoteResult.alreadyVoted);

      // Nearby neighbours add their voices until the threshold is met.
      await t.pump(const Duration(seconds: 8));
      i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.votes, 5);
      expect(i.stage, IncidentStage.requested);
      expect(c.read(waterProvider).providerQueue.single.id, i.id);

      // The pretend provider sees it, then sends trucks.
      await t.pump(const Duration(seconds: 6));
      expect(c.read(waterProvider).incidentOf('umlazi')!.stage, IncidentStage.acknowledged);
      await t.pump(const Duration(seconds: 8));
      i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.stage, IncidentStage.dispatched);
      expect(i.trucks, 3);
      expect(c.read(waterProvider).inTransit.single.id, i.id);
      expect(c.read(waterAlertsProvider).single.title, contains('3 water trucks'));

      store.resolve(i.id);
      await t.pump(const Duration(milliseconds: 200));
      expect(c.read(waterProvider).incidentOf('umlazi'), isNull);
    });

    testWidgets('with autopilot off, only the provider desk moves the request on', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final store = c.read(waterProvider.notifier)..setAutopilot(false);
      await store.vote();
      await t.pump(const Duration(seconds: 20));
      var i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.stage, IncidentStage.requested); // threshold met by neighbours
      store.acknowledge(i.id);
      await t.pump(const Duration(milliseconds: 100));
      store.dispatch(i.id, trucks: 2, etaMinutes: 45, note: 'By hand');
      await t.pump(const Duration(milliseconds: 100));
      i = c.read(waterProvider).incidentOf('umlazi')!;
      expect([i.stage, i.trucks, i.etaMinutes], [IncidentStage.dispatched, 2, 45]);
    });

    testWidgets('a dry spell drains the reservoir into Critical', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final store = c.read(waterProvider.notifier);
      final before = c.read(waterProvider).myZone!.level;
      store.runDrySpell();
      await t.pump(const Duration(seconds: 30));
      final z = c.read(waterProvider).myZone!;
      expect(z.level, lessThan(before));
      expect(z.status, WaterStatus.critical);
      expect(c.read(waterAlertsProvider).single.severity, 2);
      expect(c.read(waterProvider).dryRunning, isFalse); // it stops by itself
    });

    testWidgets('household and tank details are kept for the person', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      final store = c.read(waterProvider.notifier)
        ..setHousehold(6)
        ..setTank(1500)
        ..setHerd(4);
      await t.pump(const Duration(milliseconds: 100));
      final p = c.read(waterProvider).prefs;
      expect([p.household, p.tankLitres, p.herd], [6, 1500, 4]);
      store.setHousehold(0); // out of range is clamped
      expect(c.read(waterProvider).prefs.household, 1);
    });

    testWidgets('live mode has no demo communities, and nobody can vote', (t) async {
      final c = make();
      await t.pump(const Duration(milliseconds: 200));
      c.read(marketProvider.notifier).setDemoMode(false);
      await t.pump(const Duration(milliseconds: 300));
      final s = c.read(waterProvider);
      expect(s.demo, isFalse);
      expect(s.zones, isEmpty);
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.notEligible);
      expect(c.read(waterAlertsProvider), isEmpty);
    });
  });
}
