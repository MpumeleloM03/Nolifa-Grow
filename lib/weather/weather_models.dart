/// One day of forecast.
class DayForecast {
  final DateTime date;
  final double minC;
  final double maxC;
  final double rainMm;
  final int rainChance; // percent
  final double windKmh;

  /// Reference evapotranspiration in mm: how much water a well-watered grass
  /// surface loses that day. Null when the source did not give it.
  final double? et0;
  const DayForecast(this.date, this.minC, this.maxC, this.rainMm, this.rainChance, this.windKmh, {this.et0});

  Map<String, dynamic> toJson() => {
        'd': date.millisecondsSinceEpoch,
        'min': minC,
        'max': maxC,
        'rain': rainMm,
        'chance': rainChance,
        'wind': windKmh,
        if (et0 != null) 'et0': et0,
      };

  factory DayForecast.fromJson(Map<String, dynamic> m) => DayForecast(
        DateTime.fromMillisecondsSinceEpoch((m['d'] as num).toInt()),
        (m['min'] as num).toDouble(),
        (m['max'] as num).toDouble(),
        (m['rain'] as num).toDouble(),
        (m['chance'] as num).toInt(),
        (m['wind'] as num).toDouble(),
        et0: (m['et0'] as num?)?.toDouble(),
      );
}

/// A week of forecast for the farmer's region.
class Forecast {
  final String region;
  final List<DayForecast> days;
  final DateTime fetchedAt;

  /// The last few days as they happened, oldest first. Used to work out how
  /// much water the soil has lost since it was last watered.
  final List<DayForecast> past;

  /// True when this is a made-up forecast for the demo, not a real one.
  final bool demo;

  /// True when it is the last saved real forecast, because there is no signal.
  final bool saved;
  const Forecast(this.region, this.days, this.fetchedAt, {this.demo = false, this.saved = false, this.past = const []});

  Forecast copyWith({bool? saved}) =>
      Forecast(region, days, fetchedAt, demo: demo, saved: saved ?? this.saved, past: past);

  Map<String, dynamic> toJson() => {
        'region': region,
        'days': [for (final d in days) d.toJson()],
        'past': [for (final d in past) d.toJson()],
        'at': fetchedAt.millisecondsSinceEpoch,
      };

  factory Forecast.fromJson(Map<String, dynamic> m) => Forecast(
        m['region'] as String? ?? '',
        [for (final d in (m['days'] as List)) DayForecast.fromJson(Map<String, dynamic>.from(d as Map))],
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        past: [for (final d in (m['past'] as List? ?? const [])) DayForecast.fromJson(Map<String, dynamic>.from(d as Map))],
      );
}

/// A forecast made up for the demo: a frost in two days, a hot day, then heavy
/// rain. Clearly marked demo, used only when there is no real forecast at all.
Forecast demoForecast(String region, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  DayForecast day(int i, double min, double max, double rain, int chance, double wind) =>
      DayForecast(d0.add(Duration(days: i)), min, max, rain, chance, wind, et0: 2.0 + max / 9);
  return Forecast(
    region,
    [
      day(0, 11, 27, 0, 5, 14),
      day(1, 8, 25, 0, 10, 18),
      day(2, 0.5, 21, 0, 5, 12),
      day(3, 4, 29, 0, 5, 20),
      day(4, 12, 36, 0, 10, 28),
      day(5, 15, 24, 34, 90, 46),
      day(6, 13, 22, 18, 75, 30),
    ],
    now,
    demo: true,
    past: [
      for (var i = 5; i >= 1; i--)
        DayForecast(d0.subtract(Duration(days: i)), 11, 26, 0, 0, 12, et0: 4.6),
    ],
  );
}
