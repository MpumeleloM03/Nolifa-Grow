import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

TrafficIncident _i(String id, int cat, {int mag = 1, double lat = -29.85, double lng = 31.02, int? delay, String road = 'N2', DateTime? seen}) => TrafficIncident(
      id: id,
      category: cat,
      magnitude: mag,
      description: '',
      road: road,
      fromPlace: 'Mahatma Gandhi Rd',
      toPlace: 'Umgeni Rd',
      lat: lat,
      lng: lng,
      lengthM: 400,
      delaySeconds: delay,
      seenAt: seen ?? DateTime(2026, 10, 24, 12),
    );

void main() {
  group('which incidents matter', () {
    test('accidents, closures, flooding and breakdowns always show', () {
      for (final c in [1, 3, 8, 11, 14]) {
        expect(_i('a', c, mag: 0).worthShowing, isTrue, reason: 'category $c');
      }
    });

    test('small slowdowns and short lane closures are left out', () {
      expect(_i('a', 6, mag: 1, delay: 120).worthShowing, isFalse);
      expect(_i('a', 7, mag: 1).worthShowing, isFalse);
      expect(_i('a', 9, mag: 1).worthShowing, isFalse);
    });

    test('a long jam, or a big roadworks delay, does show', () {
      expect(_i('a', 6, mag: 2, delay: 900).worthShowing, isTrue);
      expect(_i('a', 6, mag: 3).worthShowing, isTrue);
      expect(_i('a', 9, mag: 2).worthShowing, isTrue);
    });

    test('unknown categories are not shown', () => expect(_i('a', 0, mag: 4).worthShowing, isFalse));

    test('serious means worth an interruption', () {
      expect(_i('a', 1).serious, isTrue);
      expect(_i('a', 8).serious, isTrue);
      expect(_i('a', 9, mag: 2).serious, isFalse);
      expect(_i('a', 6, mag: 4).serious, isTrue);
    });

    test('labels are plain words', () {
      expect(_i('a', 1).label, 'Accident');
      expect(_i('a', 8).label, 'Road closed');
      expect(_i('a', 11).label, 'Flooding');
      expect(_i('a', 99).label, 'Traffic incident');
    });
  });

  group('near a person', () {
    final here = (-29.85, 31.02);
    test('only incidents inside the radius, nearest first', () {
      final all = [
        _i('far', 1, lat: -29.1, lng: 31.0), // about 83 km north
        _i('mid', 1, lat: -29.95, lng: 31.02), // about 11 km
        _i('near', 8, lat: -29.86, lng: 31.02), // about 1 km
        _i('skipped', 6, mag: 1, lat: -29.851), // not worth showing
      ];
      final near = incidentsNear(all, here.$1, here.$2);
      expect(near.map((n) => n.incident.id), ['near', 'mid']);
      expect(near.first.metres, lessThan(2000));
    });

    test('a person is told about a serious incident once', () {
      final all = [_i('crash', 1, lat: -29.86), _i('works', 9, mag: 2, lat: -29.86)];
      final told = <String>{};
      final first = newSeriousNear(all, told, here.$1, here.$2);
      expect(first.map((n) => n.incident.id), ['crash'], reason: 'roadworks are not an interruption');
      told.add('crash');
      expect(newSeriousNear(all, told, here.$1, here.$2), isEmpty);
    });

    test('a serious incident outside 15 km is not pushed', () {
      final all = [_i('crash', 1, lat: -29.5)];
      expect(newSeriousNear(all, <String>{}, here.$1, here.$2), isEmpty);
    });
  });

  test('every incident says how old the data is', () {
    final now = DateTime(2026, 10, 24, 12, 7);
    expect(_i('a', 1, seen: DateTime(2026, 10, 24, 12, 5)).ageText(now), 'updated 2 min ago');
    expect(_i('a', 1, seen: DateTime(2026, 10, 24, 12, 7)).ageText(now), 'updated just now');
    expect(_i('a', 1, seen: DateTime(2026, 10, 24, 9, 0)).ageText(now), 'updated 3 h ago');
  });

  test('a road and where it runs read as one line', () {
    expect(_i('a', 1).where, 'N2  ·  Mahatma Gandhi Rd to Umgeni Rd');
  });
}
