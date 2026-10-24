import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/care/care_models.dart';
import 'package:nolifa_grow/care/care_store.dart';
import 'package:nolifa_grow/models/health_event.dart';
import 'package:nolifa_grow/models/species.dart';

HealthEvent _e(HealthKind k, DateTime at, {String? vaccine}) =>
    HealthEvent(id: '${at.microsecondsSinceEpoch}', animalId: 'a1', at: at, kind: k, condition: vaccine);

void main() {
  final now = DateTime(2026, 10, 24);

  group('vaccine standing', () {
    test('no record means not answered', () {
      expect(vaccineStatusOf(const [], now).standing, VaccineStanding.unknown);
    });

    test('a vaccination inside a year is current, older is due', () {
      expect(vaccineStatusOf([_e(HealthKind.vaccination, DateTime(2026, 3, 1), vaccine: 'Anthrax')], now).standing, VaccineStanding.current);
      expect(vaccineStatusOf([_e(HealthKind.vaccination, DateTime(2025, 6, 1))], now).standing, VaccineStanding.due);
    });

    test('saying no is kept, and a later vaccination replaces it', () {
      final no = _e(HealthKind.notVaccinated, DateTime(2026, 5, 1));
      expect(vaccineStatusOf([no], now).standing, VaccineStanding.declined);
      final yes = _e(HealthKind.vaccination, DateTime(2026, 8, 1), vaccine: 'Lumpy skin disease');
      final s = vaccineStatusOf([no, yes], now);
      expect(s.standing, VaccineStanding.current);
      expect(s.last!.condition, 'Lumpy skin disease');
    });

    test('other kinds of health event do not count', () {
      expect(vaccineStatusOf([_e(HealthKind.treatment, DateTime(2026, 9, 1))], now).standing, VaccineStanding.unknown);
    });
  });

  group('care settings', () {
    test('round trip keeps times and feed notes', () {
      const s = CareSettings(waterTimes: ['05:45'], feedTimes: ['06:00', '15:30'], feedNotes: 'Veld and lick');
      final back = CareSettings.fromJson(s.toJson());
      expect(back.waterTimes, ['05:45']);
      expect(back.feedTimes, ['06:00', '15:30']);
      expect(back.feedNotes, 'Veld and lick');
    });

    test('every species has vaccines to choose from', () {
      for (final sp in Species.values) {
        expect(vaccinesFor(sp), isNotEmpty);
      }
    });

    test('day keys sort by date', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });
}
