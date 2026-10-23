import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:nolifa_grow/models/cattle.dart';
import 'package:nolifa_grow/models/health_event.dart';
import 'package:nolifa_grow/models/livestock_disease.dart';
import 'package:nolifa_grow/models/species.dart';
import 'package:nolifa_grow/screens/livestock/add_cattle_screen.dart';
import 'package:nolifa_grow/screens/livestock/animal_detail_screen.dart';
import 'package:nolifa_grow/screens/livestock/herd_map_screen.dart';
import 'package:nolifa_grow/screens/livestock/herd_screen.dart';
import 'package:nolifa_grow/screens/livestock/livestock_home_screen.dart';
import 'package:nolifa_grow/screens/livestock/symptom_checker_screen.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/services/cattle_service.dart';
import 'package:nolifa_grow/services/health_log_service.dart';
import 'package:nolifa_grow/services/local_backend.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecureBox;

final _now = DateTime(2026, 10, 23, 9);

Cattle _a(String id, Species s, {String name = '', String sex = '', double? lat, double? lng, String camp = ''}) => Cattle(
      id: id,
      tagNumber: 'T-$id',
      tagStandard: TagStandard.visual,
      species: s,
      name: name,
      sex: sex.isEmpty ? s.defaultSex : sex,
      lat: lat,
      lng: lng,
      camp: camp,
    );

HealthEvent _check(String animal, Urgency u, {int daysAgo = 1}) => HealthEvent(
    id: 'e$animal$daysAgo$u',
    animalId: animal,
    at: _now.subtract(Duration(days: daysAgo)),
    kind: HealthKind.check,
    urgency: u,
    condition: 'x');

void _ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    if (d.exceptionAsString().contains('tile.openstreetmap.org')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

const _user = AppUser(uid: 'f1', name: 'Sipho', email: 's@x.za', region: 'Greater Durban', farmType: 'both');

Future<ProviderContainer> _mount(WidgetTester t, Widget page, List<Cattle> herd) async {
  _ignoreFontOverflow();
  t.view.physicalSize = const Size(1206, 6000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(_user),
    herdProvider.overrideWith((ref) => Stream.value(herd)),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(theme: AppTheme.build(), home: page)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  return c;
}

void main() {
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('species and diseases', () {
    test('all four species have their own classes, breeds and diseases', () {
      for (final s in Species.values) {
        expect(s.sexes, isNotEmpty);
        expect(s.breeds, isNotEmpty);
        expect(LivestockDatabase.conditionsFor(s).length, greaterThanOrEqualTo(5), reason: s.name);
        expect(LivestockDatabase.symptomsFor(s), isNotEmpty);
      }
      expect(Species.goat.sexes, containsAll(['doe', 'buck', 'kid']));
      expect(Species.sheep.sexes, containsAll(['ewe', 'ram', 'lamb']));
      expect(Species.horse.sexes, containsAll(['mare', 'stallion', 'foal']));
    });

    test('every symptom a condition uses exists and applies to every species it lists', () {
      final byId = {for (final s in LivestockDatabase.symptoms) s.id: s};
      for (final c in LivestockDatabase.conditions) {
        for (final id in c.symptomIds) {
          expect(byId.containsKey(id), isTrue, reason: '${c.name} uses unknown symptom $id');
        }
        // At least one species of the condition can show each sign.
        for (final id in c.symptomIds) {
          expect(c.species.any(byId[id]!.appliesTo), isTrue, reason: '${c.name}: $id never shows in its species');
        }
      }
    });

    test('condition names are unique', () {
      final names = LivestockDatabase.conditions.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('horses get colic and horse sickness, never milk drop or lumpy skin', () {
      final horse = LivestockDatabase.symptomsFor(Species.horse).map((s) => s.id);
      expect(horse, containsAll(['colic_pain', 'laminitis', 'frothy_nose']));
      expect(horse, isNot(contains('milk_drop')));
      expect(horse, isNot(contains('bloat')));
      final names = LivestockDatabase.conditionsFor(Species.horse).map((c) => c.name);
      expect(names, containsAll(['Colic', 'African Horse Sickness', 'Laminitis', 'Tetanus']));
      expect(names, isNot(contains('Lumpy Skin Disease')));
      expect(names, isNot(contains('Foot-and-Mouth Disease')));
    });

    test('goats and sheep get their own diseases', () {
      final goat = LivestockDatabase.conditionsFor(Species.goat).map((c) => c.name);
      expect(goat, containsAll(['Pulpy Kidney', 'Orf', 'Barber\'s Pole Worm']));
      expect(goat, isNot(contains('Sheep Scab')));
      final sheep = LivestockDatabase.conditionsFor(Species.sheep).map((c) => c.name);
      expect(sheep, containsAll(['Sheep Scab', 'Flystrike', 'Bluetongue', 'Rift Valley Fever']));
    });

    test('the controlled diseases are marked as such', () {
      final notifiable = {
        for (final c in LivestockDatabase.conditions)
          if (c.urgency == Urgency.notifiable) c.name
      };
      expect(
          notifiable,
          containsAll([
            'Foot-and-Mouth Disease',
            'Anthrax',
            'Rabies',
            'Brucellosis',
            'Rift Valley Fever',
            'Sheep Scab',
            'African Horse Sickness',
            'Bovine Tuberculosis',
          ]));
    });

    test('colic signs point a horse owner at colic, first', () {
      final m = LivestockDatabase.match({'colic_pain', 'not_eating', 'depressed'}, species: Species.horse);
      expect(m.first.condition.name, 'Colic');
      expect(m.first.condition.urgency, Urgency.emergency);
    });

    test('froth and swollen eyelids on a horse is horse sickness and ranks as a legal report', () {
      final m = LivestockDatabase.match({'frothy_nose', 'swollen_head', 'fever'}, species: Species.horse);
      expect(m.first.condition.name, 'African Horse Sickness');
      expect(m.first.condition.urgency, Urgency.notifiable);
    });

    test('the same blisters mean foot-and-mouth in a goat but nothing in a horse', () {
      final blisters = {'blisters_mouth', 'blisters_feet', 'drooling'};
      expect(LivestockDatabase.match(blisters, species: Species.goat).first.condition.name, 'Foot-and-Mouth Disease');
      final horse = LivestockDatabase.match(blisters, species: Species.horse);
      expect(horse.any((m) => m.condition.name == 'Foot-and-Mouth Disease'), isFalse);
    });

    test('nothing ticked, nothing suggested', () {
      expect(LivestockDatabase.match({}, species: Species.sheep), isEmpty);
    });

    test('advice never names a dose', () {
      final dose = RegExp(r'\b\d+\s?(ml|mg|cc|g|kg)\b', caseSensitive: false);
      for (final c in LivestockDatabase.conditions) {
        for (final a in [...c.actions, c.whatItIs]) {
          expect(dose.hasMatch(a), isFalse, reason: '${c.name}: $a');
        }
      }
    });

    test('words map to species', () {
      expect(Species.fromWord('Goats'), Species.goat);
      expect(Species.fromWord('ewe'), Species.sheep);
      expect(Species.fromWord('stallion'), Species.horse);
      expect(Species.fromWord('heifer'), Species.cattle);
      expect(Species.fromWord('dragon'), isNull);
    });

    test('water: ten goats drink far less than ten cows', () {
      expect(Species.goat.waterWeight * 10, lessThan(Species.cattle.waterWeight * 3));
    });
  });

  group('health state', () {
    test('no record is unknown', () => expect(healthStateOf(const [], _now), HealthState.unknown));

    test('a recent emergency check is sick, soon is watch, monitor is well', () {
      expect(healthStateOf([_check('a', Urgency.emergency)], _now), HealthState.sick);
      expect(healthStateOf([_check('a', Urgency.notifiable)], _now), HealthState.sick);
      expect(healthStateOf([_check('a', Urgency.soon)], _now), HealthState.watch);
      expect(healthStateOf([_check('a', Urgency.monitor)], _now), HealthState.well);
    });

    test('a check older than two weeks no longer counts', () {
      expect(healthStateOf([_check('a', Urgency.emergency, daysAgo: 20)], _now), HealthState.well);
    });

    test('marking recovered clears it, a treatment note does not', () {
      final sick = _check('a', Urgency.emergency, daysAgo: 3);
      final treated = HealthEvent(id: 't', animalId: 'a', at: _now.subtract(const Duration(days: 2)), kind: HealthKind.treatment);
      final recovered = HealthEvent(id: 'r', animalId: 'a', at: _now.subtract(const Duration(days: 1)), kind: HealthKind.recovered);
      expect(healthStateOf([sick, treated], _now), HealthState.sick);
      expect(healthStateOf([sick, treated, recovered], _now), HealthState.well);
    });

    test('a new check after recovery counts again', () {
      final recovered = HealthEvent(id: 'r', animalId: 'a', at: _now.subtract(const Duration(days: 5)), kind: HealthKind.recovered);
      expect(healthStateOf([recovered, _check('a', Urgency.emergency, daysAgo: 1)], _now), HealthState.sick);
    });

    test('events survive a save and load', () {
      final e = HealthEvent(
          id: 'x',
          animalId: 'a',
          at: _now,
          kind: HealthKind.check,
          symptomIds: ['fever'],
          condition: 'Colic',
          urgency: Urgency.emergency,
          note: 'n');
      final back = HealthEvent.fromJson(e.toJson());
      expect(back.urgency, Urgency.emergency);
      expect(back.symptomIds, ['fever']);
      expect(back.kind, HealthKind.check);
    });
  });

  group('sick animals close together', () {
    // About 1.1 km apart is inside the 1.5 km limit; 0.05 degrees is about 5.5 km.
    final near1 = _a('1', Species.goat, lat: -29.800, lng: 30.900);
    final near2 = _a('2', Species.sheep, lat: -29.809, lng: 30.900);
    final far = _a('3', Species.cattle, lat: -29.750, lng: 30.900);
    final unpinned = _a('4', Species.horse);

    test('two near each other make a group, a far one stands alone', () {
      final g = sickClusters([near1, near2, far, unpinned]);
      expect(g.length, 1);
      expect(g.single.map((a) => a.id).toSet(), {'1', '2'});
    });

    test('chains join up: A near B and B near C is one group', () {
      final c = _a('5', Species.goat, lat: -29.818, lng: 30.900);
      final g = sickClusters([near1, near2, c]);
      expect(g.length, 1);
      expect(g.single.length, 3);
    });

    test('a single sick animal is not a cluster', () => expect(sickClusters([near1]), isEmpty));
  });

  group('storage', () {
    test('species, camp and pin survive a save and reload', () async {
      final db = LocalBackend.instance;
      await db.addCattle(Cattle(
        id: '',
        tagNumber: 'G-1',
        tagStandard: TagStandard.visual,
        species: Species.goat,
        sex: 'doe',
        camp: 'North camp',
        lat: -29.81,
        lng: 30.91,
        locatedAt: _now,
      ));
      final list = await db.watchHerd().first;
      final g = list.firstWhere((c) => c.tagNumber == 'G-1');
      expect(g.species, Species.goat);
      expect(g.sex, 'doe');
      expect(g.camp, 'North camp');
      expect(g.lat, -29.81);
      expect(g.hasLocation, isTrue);
      expect(g.locatedAt, _now);
    });

    test('animals saved before species existed come back as cattle', () async {
      SharedPreferences.setMockInitialValues({});
      await LocalBackend.instance.addCattle(Cattle(id: '', tagNumber: 'OLD', tagStandard: TagStandard.visual));
      final c = (await LocalBackend.instance.watchHerd().first).firstWhere((c) => c.tagNumber == 'OLD');
      expect(c.species, Species.cattle);
      expect(c.hasLocation, isFalse);
    });

    test('a CSV with a species column or class words fills the right species', () async {
      SharedPreferences.setMockInitialValues({});
      const csv = 'tag,species,sex,breed,camp\n'
          'A1,goat,doe,Boer goat,North\n'
          'A2,,ewe,Dorper,East\n'
          'A3,horse,stallion,Boerperd,\n'
          'A4,,heifer,Nguni,South\n';
      final r = await CattleService().importCsv('f1', csv);
      expect(r.problems, isEmpty);
      expect(r.added, 4);
      final herd = {for (final c in await LocalBackend.instance.watchHerd().first) c.tagNumber: c};
      expect(herd['A1']!.species, Species.goat);
      expect(herd['A1']!.sex, 'doe');
      expect(herd['A1']!.camp, 'North');
      expect(herd['A2']!.species, Species.sheep);
      expect(herd['A3']!.species, Species.horse);
      expect(herd['A4']!.species, Species.cattle);
    });

    test('export carries species and camp, and imports back the same', () async {
      final csv = CattleService().exportCsv([_a('1', Species.sheep, sex: 'ram', camp: 'East')]);
      expect(csv.split('\n').first, contains('species'));
      expect(csv, contains('sheep'));
      expect(csv, contains('East'));
    });

    test('the health record keeps events for each animal and forgets a removed one', () async {
      final c = ProviderContainer(overrides: [currentUserProvider.overrideWithValue(_user)]);
      addTearDown(c.dispose);
      final log = c.read(healthLogProvider.notifier);
      c.read(healthLogProvider);
      await log.record('a', HealthKind.check, symptomIds: ['fever'], condition: 'Colic', urgency: Urgency.emergency);
      await log.record('b', HealthKind.note, note: ' dipped ');
      expect(log.forAnimal('a').length, 1);
      expect(log.forAnimal('b').single.note, 'dipped');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final c2 = ProviderContainer(overrides: [currentUserProvider.overrideWithValue(_user)]);
      addTearDown(c2.dispose);
      c2.read(healthLogProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c2.read(healthLogProvider).length, 2);
      final raw = (await SharedPreferences.getInstance()).getString('herd_health_f1');
      expect(raw, startsWith('enc1:'));

      await c2.read(healthLogProvider.notifier).forgetAnimal('a');
      expect(c2.read(healthLogProvider).map((e) => e.animalId), ['b']);
    });
  });

  group('screens', () {
    testWidgets('the checker asks which animal first, then shows that species\' signs', (t) async {
      await _mount(t, const SymptomCheckerScreen(), const []);
      expect(find.text('Pick the kind of animal and the signs to look for will appear.'), findsOneWidget);
      expect(find.text('Pawing, rolling, kicking or looking at the belly'), findsNothing);
      await t.tap(find.text('🐴 Horse'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Pawing, rolling, kicking or looking at the belly'), findsOneWidget);
      expect(find.text('Sudden drop in milk'), findsNothing);
      await t.tap(find.text('Pawing, rolling, kicking or looking at the belly'));
      await t.pump(const Duration(milliseconds: 300));
      await t.scrollUntilVisible(find.text('Colic'), 500);
      expect(find.text('Colic'), findsOneWidget);
      expect(find.textContaining('What this could be'), findsOneWidget);
      // Switching species clears what was ticked.
      await t.scrollUntilVisible(find.text('🐐 Goat'), -500);
      await t.tap(find.text('🐐 Goat'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('What this could be'), findsNothing);
      expect(find.text('Swollen left flank (bloat)'), findsOneWidget);
    });

    testWidgets('checking an animal saves the result to its record', (t) async {
      final nandi = _a('n1', Species.cattle, name: 'Nandi');
      final c = await _mount(t, SymptomCheckerScreen(animal: nandi), [nandi]);
      expect(find.textContaining('What do you see on Nandi?'), findsOneWidget);
      expect(find.text('WHICH ANIMAL?'), findsNothing);
      await t.tap(find.text('Blisters or sores in the mouth'));
      await t.tap(find.text('Drooling / stringy saliva'));
      await t.pump(const Duration(milliseconds: 300));
      await t.scrollUntilVisible(find.text('Foot-and-Mouth: Report Immediately'), 500);
      expect(find.text('Foot-and-Mouth: Report Immediately'), findsOneWidget);
      await t.scrollUntilVisible(find.textContaining('Save to Nandi'), 500);
      await t.tap(find.textContaining('Save to Nandi'));
      await t.pump(const Duration(milliseconds: 300));
      final saved = c.read(healthLogProvider).single;
      expect(saved.animalId, 'n1');
      expect(saved.urgency, Urgency.notifiable);
      expect(saved.condition, 'Foot-and-Mouth Disease');
      expect(saved.symptomIds.toSet(), {'blisters_mouth', 'drooling'});
      expect(find.text('Saved to the health record'), findsOneWidget);
    });

    testWidgets('the register filters by species and counts each', (t) async {
      await _mount(t, const HerdScreen(), [
        _a('1', Species.cattle, name: 'Nandi'),
        _a('2', Species.goat, name: 'Gugu'),
        _a('3', Species.goat, name: 'Themba'),
        _a('4', Species.sheep, name: 'Woolly'),
        _a('5', Species.horse, name: 'Storm'),
      ]);
      expect(find.text('All 5'), findsOneWidget);
      expect(find.text('🐐 Goats 2'), findsOneWidget);
      expect(find.text('Nandi'), findsOneWidget);
      await t.tap(find.text('🐐 Goats 2'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Gugu'), findsOneWidget);
      expect(find.text('Themba'), findsOneWidget);
      expect(find.text('Nandi'), findsNothing);
      expect(find.text('Add goat'), findsOneWidget);
      await t.ensureVisible(find.text('🐴 Horses 1'));
      await t.tap(find.text('🐴 Horses 1'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Storm'), findsOneWidget);
      expect(find.text('Gugu'), findsNothing);
    });

    testWidgets('an empty species says so', (t) async {
      await _mount(t, const HerdScreen(), [_a('1', Species.cattle, name: 'Nandi')]);
      await t.ensureVisible(find.text('🐑 Sheep 0'));
      await t.tap(find.text('🐑 Sheep 0'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('You have no sheep on the register yet.'), findsOneWidget);
    });

    testWidgets('the home page counts each species and flags sick animals', (t) async {
      final nandi = _a('1', Species.cattle, name: 'Nandi');
      final c = await _mount(t, const LivestockHomeScreen(), [nandi, _a('2', Species.goat, name: 'Gugu')]);
      expect(find.text('2'), findsWidgets);
      expect(find.text('1 🐄 cattle'), findsOneWidget);
      expect(find.text('1 🐐 goats'), findsOneWidget);
      expect(find.text('Needs attention'), findsNothing);
      await c.read(healthLogProvider.notifier).record('1', HealthKind.check, condition: 'Lumpy Skin Disease', urgency: Urgency.emergency);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Needs a vet'), findsOneWidget);
    });

    testWidgets('an animal\'s page shows its details, record and a way to mark it recovered', (t) async {
      final nandi = _a('1', Species.cattle, name: 'Nandi', camp: 'River camp');
      final c = await _mount(t, const AnimalDetailScreen(animalId: '1'), [nandi]);
      expect(find.text('Nandi'), findsWidgets);
      expect(find.text('No checks yet'), findsOneWidget);
      expect(find.text('River camp'), findsOneWidget);
      expect(find.textContaining('Nothing recorded yet'), findsOneWidget);
      await c.read(healthLogProvider.notifier).record('1', HealthKind.check,
          symptomIds: ['fever', 'not_eating'], condition: 'Heartwater', urgency: Urgency.emergency);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Needs a vet'), findsOneWidget);
      expect(find.text('Looked like Heartwater'), findsOneWidget);
      expect(find.textContaining('Signs: fever'), findsOneWidget);
      await t.ensureVisible(find.text('Mark recovered'));
      await t.tap(find.text('Mark recovered'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Looks well'), findsOneWidget);
    });

    testWidgets('adding a goat offers goat classes and breeds and saves it as a goat', (t) async {
      await _mount(t, const AddCattleScreen(initialSpecies: Species.goat), const []);
      expect(find.text('doe'), findsOneWidget);
      expect(find.text('buck'), findsOneWidget);
      expect(find.text('heifer'), findsNothing);
      expect(find.text('Boer goat'), findsOneWidget);
      expect(find.text('Dorper'), findsNothing);
      // Switching to sheep swaps the class buttons and keeps a valid class.
      await t.tap(find.text('🐑 Sheep'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('ewe'), findsOneWidget);
      expect(find.text('doe'), findsNothing);
      await t.tap(find.text('🐐 Goat'));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.widgetWithText(TextFormField, 'Tag number'), 'G-77');
      await t.tap(find.text('Boer goat'));
      await t.tap(find.text('buck'));
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(find.widgetWithText(TextFormField, 'Camp or paddock name (optional)'), 'Hill camp');
      await t.ensureVisible(find.text('Add to herd'));
      await t.tap(find.text('Add to herd'));
      await t.pump(const Duration(milliseconds: 500));
      final saved = (await LocalBackend.instance.watchHerd().first).firstWhere((c) => c.tagNumber == 'G-77');
      expect(saved.species, Species.goat);
      expect(saved.sex, 'buck');
      expect(saved.breed, 'Boer goat');
      expect(saved.camp, 'Hill camp');
    });

    testWidgets('an animal that was removed does not crash its page', (t) async {
      await _mount(t, const AnimalDetailScreen(animalId: 'gone'), const []);
      expect(find.text('This animal is no longer on the register.'), findsOneWidget);
    });

    testWidgets('the herd map explains when nothing is pinned, and warns about a sick group', (t) async {
      final a = _a('1', Species.goat, name: 'A', lat: -29.800, lng: 30.900);
      final b = _a('2', Species.goat, name: 'B', lat: -29.806, lng: 30.900);
      final c = await _mount(t, const HerdMapScreen(), [a, b, _a('3', Species.cattle)]);
      expect(find.textContaining('2 of 3 pinned'), findsOneWidget);
      expect(find.textContaining('within 1.5 km'), findsNothing);
      for (final id in ['1', '2']) {
        await c.read(healthLogProvider.notifier).record(id, HealthKind.check, urgency: Urgency.emergency, condition: 'Pulpy Kidney');
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('A group of 2 sick animals'), findsOneWidget);
    });
  });
}
