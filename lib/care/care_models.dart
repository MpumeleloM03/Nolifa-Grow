import '../models/species.dart';

/// When a farm waters and feeds its animals. Times are 24 hour "HH:mm".
class CareSettings {
  final bool remindersOn;
  final List<String> waterTimes;
  final List<String> feedTimes;

  /// What the herd is fed, in the farmer's own words. It also goes on the farm
  /// profile so a vet can see how the animals are kept.
  final String feedNotes;

  const CareSettings({
    this.remindersOn = true,
    this.waterTimes = const ['06:30', '17:00'],
    this.feedTimes = const ['07:00', '16:30'],
    this.feedNotes = '',
  });

  CareSettings copyWith({bool? remindersOn, List<String>? waterTimes, List<String>? feedTimes, String? feedNotes}) =>
      CareSettings(
        remindersOn: remindersOn ?? this.remindersOn,
        waterTimes: waterTimes ?? this.waterTimes,
        feedTimes: feedTimes ?? this.feedTimes,
        feedNotes: feedNotes ?? this.feedNotes,
      );

  Map<String, dynamic> toJson() => {
        'remindersOn': remindersOn,
        'waterTimes': waterTimes,
        'feedTimes': feedTimes,
        'feedNotes': feedNotes,
      };

  factory CareSettings.fromJson(Map<String, dynamic> m) => CareSettings(
        remindersOn: m['remindersOn'] as bool? ?? true,
        waterTimes: [for (final t in (m['waterTimes'] as List? ?? const ['06:30', '17:00'])) '$t'],
        feedTimes: [for (final t in (m['feedTimes'] as List? ?? const ['07:00', '16:30'])) '$t'],
        feedNotes: m['feedNotes'] as String? ?? '',
      );
}

/// One "I did it" tap for a slot of a day.
class CareTick {
  final String day; // yyyy-MM-dd
  final String kind; // water | feed
  final String time; // the slot, HH:mm
  final DateTime at;
  const CareTick(this.day, this.kind, this.time, this.at);

  String get key => '$day|$kind|$time';

  Map<String, dynamic> toJson() => {'day': day, 'kind': kind, 'time': time, 'at': at.millisecondsSinceEpoch};

  factory CareTick.fromJson(Map<String, dynamic> m) => CareTick(
        m['day'] as String,
        m['kind'] as String,
        m['time'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
      );
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Vaccines a South African farmer is likely to give, by species. Foot and
/// mouth and brucellosis are state controlled: they are listed so the record is
/// complete, and the state vet does them.
List<String> vaccinesFor(Species s) => switch (s) {
      Species.cattle => const [
          'Lumpy skin disease',
          'Foot and mouth (state vet)',
          'Brucellosis (state vet)',
          'Anthrax',
          'Blackleg and botulism',
          'Redwater and gallsickness',
          'Rabies',
          'Other',
        ],
      Species.sheep || Species.goat => const [
          'Pulpy kidney (enterotoxaemia)',
          'Blue tongue',
          'Rift Valley fever',
          'Anthrax',
          'Other',
        ],
      Species.horse => const ['African horse sickness', 'Tetanus', 'Rabies', 'Other'],
    };

/// A vaccination counts as current for a year.
const vaccineValidDays = 365;
