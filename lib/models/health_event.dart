import 'livestock_disease.dart';

/// What happened in an animal's health record.
enum HealthKind {
  check('Symptom check'),
  treatment('Treatment'),
  vaccination('Vaccination'),
  notVaccinated('Not vaccinated'),
  note('Note'),
  recovered('Recovered');

  final String label;
  const HealthKind(this.label);

  static HealthKind parse(String? raw) =>
      HealthKind.values.firstWhere((k) => k.name == raw, orElse: () => HealthKind.note);
}

/// One line in an animal's health record. A symptom check keeps the signs the
/// farmer ticked and the best-fitting condition, so the history can be shown to
/// a vet.
class HealthEvent {
  final String id;
  final String animalId;
  final DateTime at;
  final HealthKind kind;
  final List<String> symptomIds;
  final String? condition; // best-fitting condition name, for a symptom check
  final Urgency? urgency;
  final String note;

  const HealthEvent({
    required this.id,
    required this.animalId,
    required this.at,
    required this.kind,
    this.symptomIds = const [],
    this.condition,
    this.urgency,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'animalId': animalId,
        'at': at.millisecondsSinceEpoch,
        'kind': kind.name,
        'symptoms': symptomIds,
        'condition': condition,
        'urgency': urgency?.name,
        'note': note,
      };

  factory HealthEvent.fromJson(Map<String, dynamic> m) => HealthEvent(
        id: m['id'] as String,
        animalId: m['animalId'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        kind: HealthKind.parse(m['kind'] as String?),
        symptomIds: [for (final s in (m['symptoms'] as List? ?? const [])) s as String],
        condition: m['condition'] as String?,
        urgency: m['urgency'] == null
            ? null
            : Urgency.values.firstWhere((u) => u.name == m['urgency'], orElse: () => Urgency.monitor),
        note: m['note'] as String? ?? '',
      );
}

/// How an animal is doing, boiled down to a colour for the list and the map.
enum HealthState {
  unknown('No checks yet'),
  well('Looks well'),
  watch('Being watched'),
  sick('Needs a vet');

  final String label;
  const HealthState(this.label);
}

/// Works out the state from the record. The newest symptom check counts for 14
/// days, unless a later "recovered" line says otherwise. Treatments and notes
/// do not clear a warning: only the farmer saying "recovered" does.
HealthState healthStateOf(List<HealthEvent> events, DateTime now) {
  if (events.isEmpty) return HealthState.unknown;
  final sorted = [...events]..sort((a, b) => b.at.compareTo(a.at));
  for (final e in sorted) {
    if (e.kind == HealthKind.recovered) return HealthState.well;
    if (e.kind == HealthKind.check) {
      if (now.difference(e.at).inDays > 14) return HealthState.well;
      return switch (e.urgency) {
        Urgency.notifiable || Urgency.emergency => HealthState.sick,
        Urgency.soon => HealthState.watch,
        _ => HealthState.well,
      };
    }
  }
  return HealthState.well;
}
