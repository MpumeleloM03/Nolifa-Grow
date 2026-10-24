import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'package:ubuntu_core/water/water_widgets.dart';

// The test font (Ahem) renders every glyph a full em wide, so text rows
// overflow here that fit fine on a device. Ignore only those.
void ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

const _tab = Scaffold(body: AppBackdrop(child: SafeArea(child: WaterPage())));

/// Mounts a water screen over a fresh in-memory backend, or over [water]. [live]
/// switches the app out of demo mode; [utility] makes this person a water provider.
Future<ProviderContainer> mount(WidgetTester t, Widget home,
    {bool live = false, bool utility = false, WaterRepository? water}) async {
  ignoreFontOverflow();
  t.view.physicalSize = const Size(1206, 2622);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue('u-me'),
    marketNameProvider.overrideWithValue('Test Neighbour'),
    marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
    waterRepositoryProvider.overrideWithValue(water ?? LocalWaterRepository.memory()),
    requireVerifiedVotesProvider.overrideWithValue(false),
    if (utility) waterUtilityProvider.overrideWithValue(true),
  ]);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.build(), home: home),
  ));
  await t.pump(const Duration(milliseconds: 400));
  if (live) {
    c.read(marketProvider.notifier).setDemoMode(false);
    await t.pump(const Duration(milliseconds: 400));
  }
  return c;
}

/// Unmounts everything and stops the store's timers, so no timer outlives the test.
Future<void> finish(WidgetTester t, ProviderContainer c) async {
  await t.pumpWidget(const SizedBox());
  c.dispose();
  await t.pump(const Duration(seconds: 2));
}

void waterTest(
  String name,
  Future<void> Function(WidgetTester t, ProviderContainer c) body, {
  Widget home = _tab,
  bool live = false,
  bool utility = false,
}) {
  testWidgets(name, (t) async {
    final c = await mount(t, home, live: live, utility: utility);
    await body(t, c);
    await finish(t, c);
  });
}

/// A route or sheet needs one frame to be inserted before its transition can run.
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 1));
}

/// Scrolls the page until [f] is built, then centres it so nothing covers it.
/// Looks downwards first, then from the top, because lazy sections let go of
/// what scrolled far out of sight.
Future<void> reveal(WidgetTester t, Finder f) async {
  for (var pass = 0; pass < 2 && f.evaluate().isEmpty; pass++) {
    if (pass == 1) await scrollToTop(t);
    for (var i = 0; i < 25 && f.evaluate().isEmpty; i++) {
      await t.dragFrom(const Offset(8, 500), const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 100));
    }
  }
  expect(f, findsWidgets, reason: 'never scrolled into view');
  Scrollable.ensureVisible(t.element(f.first), alignment: 0.5);
  await t.pump(const Duration(milliseconds: 800));
}

Future<void> scrollToTop(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.dragFrom(const Offset(8, 200), const Offset(0, 600));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(const Duration(milliseconds: 500));
}

Finder inStage(String stage, Finder what) =>
    find.descendant(of: find.byKey(ValueKey('stage-$stage')), matching: what);

WaterZone oneReading({String id = 'solo', String name = 'Soloville', int threshold = 3}) => WaterZone(
      id: id,
      name: name,
      provider: 'Test Water',
      reservoir: 'Solo Reservoir',
      population: 900,
      voteThreshold: threshold,
      readings: [WaterReading(DateTime.now(), 35)],
    );

/// A shared backend that refuses provider writes while [refuse] is set, the way
/// Firestore does for a stale utility claim. Counts the attempts it was given.
class RefusingRepo extends LocalWaterRepository {
  RefusingRepo() : super.memory();

  bool refuse = false;
  VoteResult? voteResult; // set to force the answer to a vote
  int dispatchCalls = 0;
  String? lastNote;

  void _check() {
    if (refuse) throw StateError('permission-denied');
  }

  @override
  Future<VoteResult> vote(WaterZone zone, String uid, {bool dryTaps = false}) async =>
      voteResult ?? await super.vote(zone, uid, dryTaps: dryTaps);

  @override
  Future<void> publishReading(String zoneId, double level, {DateTime? at}) async {
    _check();
    await super.publishReading(zoneId, level, at: at);
  }

  @override
  Future<void> acknowledge(String incidentId) async {
    _check();
    await super.acknowledge(incidentId);
  }

  @override
  Future<void> dispatch(String incidentId, {required int trucks, required int etaMinutes, String note = ''}) async {
    dispatchCalls++;
    lastNote = note;
    _check();
    await super.dispatch(incidentId, trucks: trucks, etaMinutes: etaMinutes, note: note);
  }

  @override
  Future<void> resolve(String incidentId) async {
    _check();
    await super.resolve(incidentId);
  }
}

/// [waterTest] over a [RefusingRepo] in live mode. Opens on the provider desk.
void refusingTest(
  String name,
  Future<void> Function(WidgetTester t, ProviderContainer c, RefusingRepo repo) body, {
  Widget home = const ProviderDeskScreen(),
  bool utility = true,
}) {
  testWidgets(name, (t) async {
    final repo = RefusingRepo();
    final c = await mount(t, home, live: true, utility: utility, water: repo);
    await body(t, c, repo);
    await finish(t, c);
  });
}

/// A live community at 35% where one voice sends the request on: ready for the desk.
Future<void> seedRequest(WidgetTester t, ProviderContainer c, {int threshold = 1}) async {
  final store = c.read(waterProvider.notifier);
  await store.upsertZone(oneReading(threshold: threshold));
  await t.pump(const Duration(milliseconds: 600));
  await store.vote();
  await t.pump(const Duration(milliseconds: 600));
}

/// Lets the snackbar on screen time out and slide away, so the next one is not queued behind it.
Future<void> dismissSnack(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1)); // slide in
  await t.pump(const Duration(seconds: 5)); // time out
  await t.pump(const Duration(seconds: 1)); // slide out
}

void main() {
  group('helpers', () {
    final now = DateTime(2026, 10, 21, 14, 30);

    test('freshness reads like a person would say it', () {
      expect(agoText(null), 'never');
      expect(agoText(now, now: now), 'just now');
      expect(agoText(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(agoText(now.subtract(const Duration(hours: 2, minutes: 40)), now: now), '2 h ago');
      expect(agoText(now.subtract(const Duration(hours: 30)), now: now), '1 day ago');
      expect(agoText(now.subtract(const Duration(days: 4)), now: now), '4 days ago');
      expect(agoText(now.add(const Duration(minutes: 3)), now: now), 'just now'); // clock skew
    });

    test('times show the date only when it is not today', () {
      expect(clockText(DateTime(2026, 10, 21, 9, 5), now: now), '09:05');
      expect(clockText(DateTime(2026, 10, 20, 23, 41), now: now), '20 Oct 23:41');
    });

    test('numbers and plurals', () {
      expect(groupDigits(85000), '85 000');
      expect(groupDigits(950), '950');
      expect(groupDigits(1234567), '1 234 567');
      expect(plural(1, 'truck'), '1 truck');
      expect(plural(3, 'truck'), '3 trucks');
      expect(plural(2, 'more voice'), '2 more voices');
      expect(daysText(0.4), 'less than a day');
      expect(daysText(1.04), '1 day');
      expect(daysText(4.63), '4.6 days');
      expect(daysText(12.4), '12 days');
    });

    WaterForecast f({double? critical, double? empty, double change = -2, double confidence = 0.8}) =>
        WaterForecast(
          days: List.filled(7, 30),
          daysToLow: null,
          daysToCritical: critical,
          daysToEmpty: empty,
          changePerDay: change,
          confidence: confidence,
          why: 'x',
        );

    test('the radar headline says what is coming', () {
      expect(forecastHeadline(f(critical: 4.63, empty: 9)), 'About 4.6 days until Critical');
      expect(forecastHeadline(f(critical: 0.5, empty: 3)), 'Under a day until Critical');
      expect(forecastHeadline(f(critical: 0, empty: 5)), 'About 5 days until empty');
      expect(forecastHeadline(f(critical: 0, empty: 1.4)), 'About 1.4 days until empty');
      expect(forecastHeadline(f(critical: 0, empty: 0.8)), 'Under a day until empty');
      expect(forecastHeadline(f(critical: 0, empty: 0)), 'Critical now');
      expect(forecastHeadline(f(change: 0.1)), 'Steady');
      expect(forecastHeadline(f(change: 2)), 'Recovering');
      expect(forecastHeadline(f(confidence: 0)), 'Not enough readings yet');
    });

    test('the headline colour follows the urgency', () {
      expect(forecastColor(f(critical: 1)), AppTheme.danger);
      expect(forecastColor(f(critical: 5)), AppTheme.warn);
      expect(forecastColor(f(critical: 12)), AppTheme.ok);
      expect(forecastColor(f()), AppTheme.ok);
    });

    test('the newest incident wins, even once resolved', () {
      WaterIncident inc(int epoch, IncidentStage stage, {String zone = 'a'}) => WaterIncident(
            id: '$zone-$epoch',
            zoneId: zone,
            epoch: epoch,
            stage: stage,
            votes: 1,
            threshold: 3,
            openedAt: now,
          );
      final all = [inc(1, IncidentStage.resolved), inc(2, IncidentStage.resolved), inc(1, IncidentStage.open, zone: 'b')];
      expect(newestIncident(all, 'a')!.epoch, 2);
      expect(newestIncident(all, 'b')!.stage, IncidentStage.open);
      expect(newestIncident(all, 'c'), isNull);
    });
  });

  group('the community page', () {
    waterTest('shows the home community, its status and a forecast headline', (t, c) async {
      expect(find.text('Water'), findsOneWidget);
      expect(find.text("Your community's supply, forecast and help"), findsOneWidget);
      expect(find.text('Umlazi'), findsOneWidget);
      expect(find.text('eThekwini Water (demo)'), findsOneWidget);
      expect(find.textContaining('Updated'), findsOneWidget);
      expect(find.text('Provider feed (demo)'), findsOneWidget); // simulated data says so
      expect(find.text('Low'), findsWidgets);
      expect(find.text('Umlazi Reservoir'), findsOneWidget);
      expect(find.text('85 000 people served'), findsOneWidget);

      await reveal(t, find.text('Water radar'));
      expect(find.text("Forecast from the reservoir's readings"), findsOneWidget);
      expect(find.textContaining('until Critical'), findsOneWidget);
      expect(find.textContaining('Falling'), findsOneWidget);
      expect(find.text('Days to empty'), findsOneWidget);
      expect(find.text('Confidence'), findsOneWidget);
      // The 7-day chart is drawn, not faked with text.
      expect(find.byType(WaterRadarChart), findsOneWidget);
    });

    waterTest('picking another community switches the whole page', (t, c) async {
      await t.ensureVisible(find.text('KwaMashu'));
      await t.tap(find.text('KwaMashu'));
      await t.pump(const Duration(milliseconds: 600));
      expect(c.read(waterProvider).myZone!.id, 'kwamashu');
      expect(find.text('KwaMashu Reservoir'), findsOneWidget);
      expect(find.text('64 000 people served'), findsOneWidget);
    });

    waterTest('a healthy community gets a calm card instead of a button', (t, c) async {
      c.read(waterProvider.notifier).selectZone('chatsworth');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('Chatsworth Reservoir'), findsOneWidget);
      await reveal(t, find.text('No help needed right now'));
      expect(find.text('The dams behind Chatsworth are 74% full. A full dam does not always mean a running tap.'), findsOneWidget);
      expect(find.text('Ask for water help'), findsNothing);
    });

    waterTest('a healthy dam still lets people say their taps are dry', (t, c) async {
      c.read(waterProvider.notifier).selectZone('chatsworth');
      await t.pump(const Duration(milliseconds: 600));
      await reveal(t, find.text('My taps are dry'));
      expect(c.read(waterProvider).incidentOf('chatsworth'), isNull);
      await t.tap(find.text('My taps are dry'));
      await t.pump(const Duration(milliseconds: 600));
      final i = c.read(waterProvider).incidentOf('chatsworth');
      expect(i, isNotNull);
      expect(i!.votes, 1);
      // A plain request on a healthy dam is still turned away.
      expect(await c.read(waterProvider.notifier).vote(), VoteResult.alreadyVoted);
    });

    waterTest('host sections are slotted in', (t, c) async {
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const Scaffold(
            body: AppBackdrop(
              child: SafeArea(child: WaterPage(extraSections: [GlassCard(child: Text('Farm water use'))])),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
      await reveal(t, find.text('Farm water use'));
      expect(find.text('Farm water use'), findsOneWidget);
    });

    waterTest('the full screen has a back button', (t, c) async {
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterScreen())),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await settle(t);
      expect(find.text('Your community'), findsOneWidget);
      await t.tap(find.byTooltip('Back'));
      await settle(t);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('community voice', () {
    waterTest('asking for help counts the vote and locks the button', (t, c) async {
      await reveal(t, find.text('Ask for water help'));
      expect(find.text('Be the first to ask'), findsOneWidget);
      expect(find.textContaining('When 5 neighbours ask, the request goes to eThekwini Water (demo)'), findsOneWidget);

      await t.tap(find.text('Ask for water help'));
      await t.pump(const Duration(milliseconds: 200));

      final i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.votes, 1);
      expect(c.read(waterProvider).votedIn(i), isTrue);
      expect(find.text('Ask for water help'), findsNothing);
      expect(find.text('4 more voices needed'), findsOneWidget);
      final done = t.widget<GlassButton>(find.widgetWithText(GlassButton, 'You asked for help'));
      expect(done.onPressed, isNull); // disabled
      expect(inStage('open', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
      expect(inStage('requested', find.byIcon(Icons.check_circle_rounded)), findsNothing);
    });

    waterTest('neighbours push it to the threshold and the timeline shows Sent to the provider', (t, c) async {
      c.read(waterProvider.notifier).setAutopilot(false); // keep the pretend provider quiet
      await reveal(t, find.text('Ask for water help'));
      await t.tap(find.text('Ask for water help'));
      await t.pump(const Duration(seconds: 8));

      final i = c.read(waterProvider).incidentOf('umlazi')!;
      expect(i.votes, 5);
      expect(i.stage, IncidentStage.requested);

      expect(find.text('Your request is with eThekwini Water (demo)'), findsOneWidget);
      expect(inStage('requested', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
      expect(inStage('requested', find.textContaining(':')), findsOneWidget); // the real time
      expect(inStage('acknowledged', find.byIcon(Icons.check_circle_rounded)), findsNothing);
      expect(inStage('dispatched', find.byIcon(Icons.check_circle_rounded)), findsNothing);
      expect(find.text('Sent to the provider'), findsOneWidget);
    });
  });

  group('asking once the request is with the provider', () {
    refusingTest('someone new is not offered the button after Acknowledge, and sees where it stands', (t, c, repo) async {
      // Another person's voice sends the request on, and the provider has seen it.
      final zone = oneReading(threshold: 1);
      await c.read(waterProvider.notifier).upsertZone(zone);
      await repo.vote(zone, 'someone-else');
      await repo.acknowledge('solo-1');
      await t.pump(const Duration(milliseconds: 600));

      await reveal(t, find.text('Community voice'));
      expect(c.read(waterProvider).incidentOf('solo')!.stage, IncidentStage.acknowledged);
      expect(find.text('Test Water has seen your request'), findsOneWidget);
      expect(find.text('Ask for water help'), findsNothing);
      expect(find.text('You asked for help'), findsNothing);
      expect(inStage('acknowledged', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    }, home: _tab, utility: false);

    refusingTest('a vote the backend turns away on a low supply says the request has moved on', (t, c, repo) async {
      await c.read(waterProvider.notifier).upsertZone(oneReading());
      repo.voteResult = VoteResult.notEligible; // the request reached the provider as this person tapped
      await t.pump(const Duration(milliseconds: 600));

      await reveal(t, find.text('Ask for water help'));
      await t.tap(find.text('Ask for water help'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('This request is already with the provider.'), findsOneWidget);
      expect(find.textContaining('below 40%'), findsNothing); // the supply is already low
    }, home: _tab, utility: false);
  });

  group('the provider desk', () {
    waterTest('lists the request; Acknowledge then Send trucks reaches the community', (t, c) async {
      final store = c.read(waterProvider.notifier)..setAutopilot(false);
      await store.vote();
      await t.pump(const Duration(seconds: 8));
      expect(c.read(waterProvider).incidentOf('umlazi')!.stage, IncidentStage.requested);

      await reveal(t, find.text('Open provider desk'));
      await t.tap(find.text('Open provider desk'));
      await settle(t);

      expect(find.text('Provider desk'), findsOneWidget);
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('Needs an answer'), findsOneWidget);
      expect(find.text('Umlazi'), findsWidgets);
      expect(find.text('Sent to the provider'), findsOneWidget);
      expect(find.textContaining('of 5 needed'), findsOneWidget);
      expect(find.text('85 000'), findsOneWidget);
      expect(find.textContaining('Reached the provider'), findsOneWidget);

      await t.tap(find.text('Acknowledge'));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(waterProvider).incidentOf('umlazi')!.stage, IncidentStage.acknowledged);
      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Provider has seen it'), findsOneWidget);

      await t.tap(find.text('Send trucks'));
      await settle(t);
      expect(find.text('Send 2 trucks now'), findsOneWidget);
      await t.tap(find.byTooltip('Increase trucks'));
      await t.tap(find.byTooltip('Increase arrival time'));
      await t.tap(find.byTooltip('Increase arrival time'));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('dispatch-note')), 'Fill the green tanks');
      expect(find.text('Send 3 trucks now'), findsOneWidget);
      expect(find.text('90 min'), findsOneWidget);
      await t.tap(find.text('Send 3 trucks now'));
      await settle(t);

      final sent = c.read(waterProvider).inTransit.single;
      expect([sent.trucks, sent.etaMinutes, sent.note], [3, 90, 'Fill the green tanks']);
      expect(c.read(waterProvider).providerQueue, isEmpty);
      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('Mark delivered'), findsOneWidget);

      // Back on the community page the trucks, ETA and note are front and centre.
      await t.tap(find.byTooltip('Back'));
      await settle(t);
      await reveal(t, find.text('3 trucks on the way'));
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(find.text('90 min'), findsOneWidget);
      expect(find.textContaining('min left'), findsOneWidget);
      expect(find.text('Fill the green tanks'), findsOneWidget);
      expect(find.text('Ask for water help'), findsNothing); // the request is answered
      expect(inStage('dispatched', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    });

    waterTest('marking the trucks delivered resolves the request', (t, c) async {
      final store = c.read(waterProvider.notifier)..setAutopilot(false);
      await store.vote();
      await t.pump(const Duration(seconds: 8));
      final id = c.read(waterProvider).incidentOf('umlazi')!.id;
      store.dispatch(id, trucks: 1, etaMinutes: 30, note: 'One tanker');
      await t.pump(const Duration(milliseconds: 300));

      await reveal(t, find.text('Open provider desk'));
      await t.tap(find.text('Open provider desk'));
      await settle(t);
      expect(find.text('On the road'), findsOneWidget);
      expect(find.text('One tanker'), findsOneWidget);
      expect(find.text('1 truck'), findsOneWidget);

      await t.tap(find.text('Mark delivered'));
      await t.pump(const Duration(milliseconds: 500));
      expect(c.read(waterProvider).incidentOf('umlazi'), isNull);
      expect(find.text('No trucks on the road'), findsOneWidget);

      await t.tap(find.byTooltip('Back'));
      await settle(t);
      await reveal(t, find.textContaining('Last request resolved at'));
      expect(find.textContaining('1 truck delivered'), findsOneWidget);
      // Supply is still Low, so people can ask again for a new shortage.
      expect(find.text('Ask for water help'), findsOneWidget);
    });

    waterTest('lists every community with its level, status and forecast', (t, c) async {
      await reveal(t, find.text('Open provider desk'));
      await t.tap(find.text('Open provider desk'));
      await settle(t);
      await reveal(t, find.text('Communities'));
      for (final name in ['Chatsworth', 'Inanda']) {
        await reveal(t, find.text(name));
      }
      expect(find.text('Steady'), findsWidgets); // Chatsworth is flat
      expect(find.textContaining('until Critical'), findsWidgets);
    });

    waterTest('publishing a reading changes the community for everyone', (t, c) async {
      await reveal(t, find.text('Open provider desk'));
      await t.tap(find.text('Open provider desk'));
      await settle(t);

      await reveal(t, find.text('Publish a reading'));
      await t.tap(find.widgetWithText(WaterChip, 'KwaMashu'));
      await t.pump(const Duration(milliseconds: 300));
      t.widget<Slider>(find.byType(Slider)).onChanged!(12);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('12%'), findsWidgets);
      await reveal(t, find.widgetWithText(GlassButton, 'Publish'));
      await t.tap(find.widgetWithText(GlassButton, 'Publish'));
      await t.pump(const Duration(milliseconds: 500));

      final z = c.read(waterProvider).zones.firstWhere((z) => z.id == 'kwamashu');
      expect(z.level, 12);
      expect(z.status, WaterStatus.critical);
      expect(z.readings.length, 29);
      expect(find.text('Published 12% for KwaMashu'), findsOneWidget);
    });
  });

  group('the desk when you are not the provider', () {
    waterTest('says the desk is for the water provider', (t, c) async {
      expect(find.text('This desk is for the water provider'), findsOneWidget);
      expect(find.text('Needs an answer'), findsNothing);
      expect(find.text('Publish a reading'), findsNothing);
    }, home: const ProviderDeskScreen(), live: true);

    waterTest('adds a community with an honest single reading', (t, c) async {
      final store = c.read(waterProvider.notifier);
      expect(store.isProvider, isTrue);
      expect(find.text('Demo'), findsNothing); // live data
      expect(find.text('No communities yet'), findsOneWidget);

      await reveal(t, find.widgetWithText(GhostButton, 'Add community'));
      await t.tap(find.widgetWithText(GhostButton, 'Add community'));
      await settle(t);

      // Empty fields are refused.
      await t.tap(find.widgetWithText(GlassButton, 'Add community'));
      await t.pump();
      expect(find.text('Required'), findsWidgets);
      expect(find.text('Enter a number above 0'), findsOneWidget);
      expect(c.read(waterProvider).zones, isEmpty);

      await t.enterText(find.byKey(const ValueKey('add-name')), 'Embo');
      await t.enterText(find.byKey(const ValueKey('add-provider')), 'uMngeni Water');
      await t.enterText(find.byKey(const ValueKey('add-people')), '12000');
      await t.enterText(find.byKey(const ValueKey('add-votes')), '3');
      t.widget<Slider>(find.byKey(const ValueKey('add-level'))).onChanged!(15);
      await t.pump();
      await t.tap(find.widgetWithText(GlassButton, 'Add community'));
      await settle(t);

      final z = c.read(waterProvider).zones.single;
      expect([z.id, z.name, z.provider, z.reservoir], ['embo', 'Embo', 'uMngeni Water', 'Embo Reservoir']);
      expect([z.population, z.voteThreshold, z.demo], [12000, 3, false]);
      expect(z.readings.length, 1); // no invented history
      expect(z.level, 15);
      expect(c.read(waterProvider).forecastOf('embo')!.confidence, 0);

      await reveal(t, find.text('Communities'));
      expect(find.text('Embo'), findsWidgets);
      expect(find.text('Not enough readings yet'), findsOneWidget);
      expect(find.text('Embo added'), findsOneWidget);

      // The same name again gets its own id rather than overwriting.
      await reveal(t, find.widgetWithText(GhostButton, 'Add community'));
      await t.tap(find.widgetWithText(GhostButton, 'Add community'));
      await settle(t);
      expect(t.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('add-provider')), matching: find.byType(TextField))).controller!.text,
          'uMngeni Water'); // remembered from the first community
      await t.enterText(find.byKey(const ValueKey('add-name')), 'Embo');
      await t.enterText(find.byKey(const ValueKey('add-people')), '800');
      await t.tap(find.widgetWithText(GlassButton, 'Add community'));
      await settle(t);
      expect(c.read(waterProvider).zones.map((z) => z.id).toSet(), {'embo', 'embo-2'});
    }, home: const ProviderDeskScreen(), live: true, utility: true);
  });

  group('preparing for the worst case', () {
    waterTest('works out litres, cover and bottles, and fills the cart', (t, c) async {
      final s = c.read(waterProvider);
      final plan = planWater(prefs: s.prefs, forecast: s.forecastOf('umlazi')!);
      // Umlazi falls about 2.9% a day from 33%, so Critical is 4.6 days out: plan for 5.
      expect(plan.daysToCover, 5);
      expect(plan.bottles, 12); // 4 people x 15 L x 5 days = 300 L = 12 bottles of 25 L

      await reveal(t, find.text('Order 12 water bottles'));
      expect(find.text('60 L a day'), findsOneWidget);
      expect(find.text('0.0 days'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
      expect(find.widgetWithText(StatTile, '300 L'), findsOneWidget);
      expect(find.text('12 x 25 L = 300 L for R540, delivered by a neighbour.'), findsOneWidget);

      // One more person at home: 75 L a day, 375 L, 15 bottles.
      await reveal(t, find.byTooltip('Increase people'));
      await t.tap(find.byTooltip('Increase people'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('75 L a day'), findsOneWidget);
      expect(find.text('Order 15 water bottles'), findsOneWidget);
      await t.tap(find.byTooltip('Decrease people'));
      await t.pump(const Duration(milliseconds: 300));

      // Water already stored comes off the shortfall: 300 - 250 = 50 L = 2 bottles.
      await reveal(t, find.byTooltip('Increase water stored'));
      await t.tap(find.byTooltip('Increase water stored'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('250 L'), findsOneWidget);
      expect(find.text('4.2 days'), findsOneWidget); // 250 L at 60 L a day
      expect(find.text('Order 2 water bottles'), findsOneWidget);

      // One bottle is already in the cart: the order tops it up to 2, not 3.
      c.read(marketProvider.notifier).add('p-water');
      await reveal(t, find.text('Order 2 water bottles'));
      await t.tap(find.text('Order 2 water bottles'));
      await settle(t);
      expect(c.read(marketProvider).cart['p-water'], 2);
      expect(find.byType(CheckoutScreen), findsOneWidget);

      // Back out and tap again: still 2, never doubled.
      await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await settle(t);
      await reveal(t, find.text('Order 2 water bottles'));
      await t.tap(find.text('Order 2 water bottles'));
      await settle(t);
      expect(c.read(marketProvider).cart['p-water'], 2);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    waterTest('the order sets the cart to the number on the button, even when it holds more', (t, c) async {
      c.read(marketProvider.notifier).add('p-water', 20);
      await reveal(t, find.text('Order 12 water bottles'));
      await t.tap(find.text('Order 12 water bottles'));
      await settle(t);
      expect(c.read(marketProvider).cart['p-water'], 12);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    waterTest('one bottle reads in the singular', (t, c) async {
      c.read(waterProvider.notifier)
        ..setHousehold(1)
        ..setTank(60);
      await t.pump(const Duration(milliseconds: 300));
      final s = c.read(waterProvider);
      expect(planWater(prefs: s.prefs, forecast: s.forecastOf('umlazi')!).bottles, 1); // 75 L - 60 L stored
      await reveal(t, find.text('Order 1 water bottle'));
      expect(find.text('1 x 25 L = 25 L for R45, delivered by a neighbour.'), findsOneWidget);
    });

    waterTest('enough stored water shows You are covered and no order button', (t, c) async {
      await reveal(t, find.widgetWithText(WaterChip, '500 L'));
      expect(find.text('You are covered'), findsNothing);
      await t.tap(find.widgetWithText(WaterChip, '500 L'));
      await t.pump(const Duration(milliseconds: 500));
      await reveal(t, find.text('You are covered'));
      expect(find.text('500 L lasts 8.3 days, enough for the 5 days we plan for.'), findsOneWidget);
      expect(find.textContaining('Order '), findsNothing);
      expect(find.widgetWithText(StatTile, '0 L'), findsOneWidget); // short by nothing
    });

    waterTest('livestock only shows for people who keep it', (t, c) async {
      final store = c.read(waterProvider.notifier);
      await reveal(t, find.text('If it runs dry'));
      expect(find.textContaining('Livestock'), findsNothing);
      store.setHerd(10);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Livestock: 10 head need 500 L a day'), findsOneWidget);
      expect(find.text('560 L a day'), findsOneWidget); // 4 x 15 + 10 x 50
      store.setHerd(0);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Livestock'), findsNothing);
    });

    waterTest('the checklist ticks stay ticked while the page is open', (t, c) async {
      const item = 'Delay washing and irrigation';
      bool struck() => t.widget<Text>(find.text(item)).style!.decoration == TextDecoration.lineThrough;

      await reveal(t, find.text(item));
      expect(struck(), isFalse);
      await t.tap(find.text(item));
      await t.pump(const Duration(milliseconds: 300));
      expect(struck(), isTrue);

      await scrollToTop(t);
      expect(find.text(item), findsNothing); // the section was scrolled away and let go
      await reveal(t, find.text(item));
      expect(struck(), isTrue);
      expect(t.widget<Text>(find.text('Fill every container now')).style!.decoration, isNull);
    });
  });

  group('demo controls', () {
    waterTest('Run dry spell drains the reservoir and shows progress', (t, c) async {
      await reveal(t, find.text('Demo controls'));
      expect(find.text('Simulated'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final before = c.read(waterProvider).myZone!.level;

      await t.tap(find.text('Run dry spell'));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(waterProvider).dryRunning, isTrue);
      expect(find.text('Run dry spell'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final busy = t.widget<GlassButton>(find.widgetWithText(GlassButton, 'Draining the reservoir'));
      expect(busy.onPressed, isNull); // disabled while it runs

      await t.pump(const Duration(seconds: 30));
      final z = c.read(waterProvider).myZone!;
      expect(z.level, lessThan(before));
      expect(z.status, WaterStatus.critical);
      // However close to empty it gets, the headline stays grammatical.
      expect(forecastHeadline(c.read(waterProvider).forecastOf('umlazi')!), isNot(contains('About less')));
      expect(find.text('Run dry spell'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await scrollToTop(t);
      expect(find.text('Critical'), findsWidgets); // the supply card follows the reservoir
    });

    waterTest('Reset demo stops a dry spell and clears the request', (t, c) async {
      final store = c.read(waterProvider.notifier);
      await store.vote();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(waterProvider).incidentOf('umlazi'), isNotNull);

      await reveal(t, find.text('Run dry spell'));
      await t.tap(find.text('Run dry spell'));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(waterProvider).dryRunning, isTrue);

      await reveal(t, find.text('Reset demo'));
      await t.tap(find.text('Reset demo'));
      await t.pump(const Duration(milliseconds: 300));
      final s = c.read(waterProvider);
      expect(s.dryRunning, isFalse);
      expect(s.incidents, isEmpty);
      expect(s.myVotes, isEmpty);
      await reveal(t, find.text('Ask for water help'));
    });

    waterTest('the switch turns the pretend provider off and on', (t, c) async {
      await reveal(t, find.text('Pretend provider answers by itself'));
      expect(c.read(waterProvider).autopilot, isTrue);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
      await t.tap(find.byType(Switch));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(waterProvider).autopilot, isFalse);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    waterTest('are hidden in live mode', (t, c) async {
      expect(c.read(waterProvider).demo, isFalse);
      await reveal(t, find.text('If it runs dry'));
      for (var i = 0; i < 6; i++) {
        await t.dragFrom(const Offset(8, 500), const Offset(0, -400));
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Demo controls'), findsNothing);
      expect(find.text('Run dry spell'), findsNothing);
      expect(find.text('Reset demo'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    }, live: true);
  });

  group('when the backend refuses a provider write', () {
    const sendLabel = 'Send 2 trucks now';
    const cannotSend = 'Could not send. Check your permission and connection.';

    refusingTest('a refused dispatch keeps the sheet open and the request unchanged', (t, c, repo) async {
      await seedRequest(t, c);
      expect(c.read(waterProvider).incidentOf('solo')!.stage, IncidentStage.requested);

      await t.tap(find.text('Send trucks'));
      await settle(t);
      repo.refuse = true;
      await t.tap(find.text(sendLabel));
      await settle(t);

      expect(repo.dispatchCalls, 1);
      expect(find.text(cannotSend), findsOneWidget);
      expect(find.text(sendLabel), findsOneWidget); // still open
      expect(c.read(waterProvider).incidentOf('solo')!.stage, IncidentStage.requested);
      expect(c.read(waterProvider).inTransit, isEmpty);

      // Once the permission is back the same sheet goes through, and only then closes.
      repo.refuse = false;
      await t.tap(find.text(sendLabel));
      await settle(t);
      expect(find.text(sendLabel), findsNothing);
      expect(c.read(waterProvider).inTransit.single.trucks, 2);
      expect(find.text('Mark delivered'), findsOneWidget);
    });

    refusingTest('a refused acknowledge says so and leaves the request waiting', (t, c, repo) async {
      await seedRequest(t, c);
      repo.refuse = true;
      await t.tap(find.text('Acknowledge'));
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('Could not acknowledge. Check your permission and connection.'), findsOneWidget);
      expect(c.read(waterProvider).incidentOf('solo')!.stage, IncidentStage.requested);
      expect(find.text('Acknowledge'), findsOneWidget);
    });

    refusingTest('a refused delivery stays on the road and says so', (t, c, repo) async {
      await seedRequest(t, c);
      final id = c.read(waterProvider).incidentOf('solo')!.id;
      await c.read(waterProvider.notifier).dispatch(id, trucks: 1, etaMinutes: 30);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Mark delivered'), findsOneWidget);

      repo.refuse = true;
      await t.tap(find.text('Mark delivered'));
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('Could not mark delivered. Check your permission and connection.'), findsOneWidget);
      expect(c.read(waterProvider).incidentOf('solo')!.stage, IncidentStage.dispatched);
      expect(find.text('Mark delivered'), findsOneWidget);
    });

    refusingTest('a refused reading is not reported as published', (t, c, repo) async {
      await c.read(waterProvider.notifier).upsertZone(oneReading());
      await t.pump(const Duration(milliseconds: 600));
      await reveal(t, find.text('Publish a reading'));
      t.widget<Slider>(find.byType(Slider)).onChanged!(12);
      await t.pump(const Duration(milliseconds: 300));

      repo.refuse = true;
      await reveal(t, find.widgetWithText(GlassButton, 'Publish'));
      await t.tap(find.widgetWithText(GlassButton, 'Publish'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Could not publish. Check your permission and connection.'), findsOneWidget);
      expect(find.textContaining('Published'), findsNothing);
      expect(c.read(waterProvider).zones.single.readings.length, 1);
      expect(t.widget<Slider>(find.byType(Slider)).value, 12); // kept, so it can be tried again

      await dismissSnack(t);
      repo.refuse = false;
      await t.tap(find.widgetWithText(GlassButton, 'Publish'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Published 12% for Soloville'), findsOneWidget);
      expect(c.read(waterProvider).zones.single.readings.length, 2);
    });

    refusingTest('a note over 280 characters is stopped before it is sent', (t, c, repo) async {
      await seedRequest(t, c);
      await t.tap(find.text('Send trucks'));
      await settle(t);

      await t.enterText(find.byKey(const ValueKey('dispatch-note')), 'w' * 281);
      await t.tap(find.text(sendLabel));
      await settle(t);
      expect(find.text('Keep the note to 280 characters or fewer'), findsOneWidget);
      expect(repo.dispatchCalls, 0); // nothing reached the backend
      expect(c.read(waterProvider).inTransit, isEmpty);

      // Exactly 280 is what the rules allow.
      await t.enterText(find.byKey(const ValueKey('dispatch-note')), 'w' * 280);
      await t.tap(find.text(sendLabel));
      await settle(t);
      expect(repo.lastNote, 'w' * 280);
      expect(c.read(waterProvider).inTransit.single.note.length, 280);
    });

    refusingTest('the add-community form keeps to the lengths the rules accept', (t, c, repo) async {
      await reveal(t, find.widgetWithText(GhostButton, 'Add community'));
      await t.tap(find.widgetWithText(GhostButton, 'Add community'));
      await settle(t);

      await t.enterText(find.byKey(const ValueKey('add-name')), 'n' * 81);
      await t.enterText(find.byKey(const ValueKey('add-provider')), 'p' * 81);
      await t.enterText(find.byKey(const ValueKey('add-reservoir')), 'r' * 81);
      await t.enterText(find.byKey(const ValueKey('add-people')), '500');
      await t.enterText(find.byKey(const ValueKey('add-votes')), '100001');
      await t.tap(find.widgetWithText(GlassButton, 'Add community'));
      await t.pump();
      expect(find.text('Use 80 characters or fewer'), findsNWidgets(3));
      expect(find.text('Enter a number from 1 to 100 000'), findsOneWidget);
      expect(c.read(waterProvider).zones, isEmpty);

      // A name that fits but would push "<name> Reservoir" past 80 keeps the name alone.
      await t.enterText(find.byKey(const ValueKey('add-name')), 'n' * 75);
      await t.enterText(find.byKey(const ValueKey('add-provider')), 'Water Board');
      await t.enterText(find.byKey(const ValueKey('add-reservoir')), '');
      await t.enterText(find.byKey(const ValueKey('add-votes')), '100000');
      await t.tap(find.widgetWithText(GlassButton, 'Add community'));
      await settle(t);
      final z = c.read(waterProvider).zones.single;
      expect(z.reservoir, 'n' * 75);
      expect(z.reservoir.length, lessThanOrEqualTo(80));
      expect(z.voteThreshold, 100000);
    });
  });

  group('live mode', () {
    waterTest('with no readings it explains, and still lets people prepare', (t, c) async {
      expect(find.text('No readings for your area yet'), findsOneWidget);
      expect(find.textContaining('has not shared data for this area yet'), findsOneWidget);
      expect(find.text('Provider feed (demo)'), findsNothing);
      expect(find.text('Water radar'), findsNothing);
      expect(find.text('Community voice'), findsNothing);

      await reveal(t, find.text('If it runs dry'));
      expect(find.text('People at home'), findsOneWidget);
      // With nothing forecast, plan for the 3-day minimum: 4 people x 15 L x 3.
      expect(find.text('Planning for'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('180 L'), findsOneWidget);
      // The demo's water product is not on sale in live mode, so there is no order button.
      expect(find.textContaining('Order '), findsNothing);
      expect(find.textContaining('not on sale in your area yet'), findsOneWidget);
      expect(find.text('Open provider desk'), findsNothing);
    }, live: true);

    waterTest('a community with one reading says the radar needs more', (t, c) async {
      await c.read(waterProvider.notifier).upsertZone(oneReading());
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Soloville'), findsOneWidget);
      expect(find.text('Test Water'), findsOneWidget);
      expect(find.text('Provider feed (demo)'), findsNothing);

      await reveal(t, find.text('Water radar'));
      expect(find.text('Not enough readings yet'), findsOneWidget);
      expect(find.textContaining('at least 4 readings'), findsOneWidget);
      expect(find.byType(WaterRadarChart), findsNothing);
      expect(find.textContaining('None yet'), findsOneWidget);
      // At 35% it is Low, so the community can already ask for help.
      await reveal(t, find.text('Ask for water help'));
      expect(find.textContaining('When 3 neighbours ask, the request goes to Test Water'), findsOneWidget);
    }, live: true, utility: true);

    waterTest('a provider can reach the desk from the page', (t, c) async {
      await reveal(t, find.text('Open provider desk'));
      await t.tap(find.text('Open provider desk'));
      await settle(t);
      expect(find.text('Provider desk'), findsOneWidget);
      expect(find.text('Needs an answer'), findsOneWidget);
    }, live: true, utility: true);
  });
}
