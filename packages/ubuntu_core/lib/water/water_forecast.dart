import 'dart:math' as math;
import 'water_models.dart';

/// The water radar's forecast.
///
/// This is a statistical model, not magic: Holt's double exponential smoothing
/// over the reservoir readings, which tracks both the level and how fast it is
/// changing, then projects that forward. It is cheap, explainable, and works
/// offline. [demand] (0.15 means 15% more) and [rain] (0.15 means inflow 15%
/// better) let known conditions such as a heatwave or a rain forecast bend the
/// trend without hiding what the readings say.
WaterForecast forecastWater(
  List<WaterReading> readings, {
  int horizonDays = 7,
  double demand = 0,
  double rain = 0,
}) {
  if (readings.length < 4) {
    final lvl = readings.isEmpty ? 0.0 : readings.last.level;
    return WaterForecast(
      days: List.filled(horizonDays, lvl),
      daysToLow: null,
      daysToCritical: null,
      daysToEmpty: null,
      changePerDay: 0,
      confidence: 0,
      why: 'Not enough readings yet to forecast.',
    );
  }

  // Readings are evenly spaced; work out how many fall in a day.
  final span = readings.last.at.difference(readings.first.at).inMinutes;
  final stepMin = span / (readings.length - 1);
  final stepsPerDay = stepMin <= 0 ? 1.0 : 1440 / stepMin;

  const alpha = 0.6;
  const beta = 0.3;
  var level = readings.first.level;
  var trend = readings[1].level - readings[0].level;
  var absErr = 0.0;
  for (var i = 1; i < readings.length; i++) {
    final predicted = level + trend;
    absErr += (readings[i].level - predicted).abs();
    final prev = level;
    level = alpha * readings[i].level + (1 - alpha) * (level + trend);
    trend = beta * (level - prev) + (1 - beta) * trend;
  }

  // Bend the trend for known conditions: more demand speeds a fall, rain slows it.
  var perStep = trend;
  if (perStep < 0) {
    perStep *= (1 + demand) * (1 - rain).clamp(0.0, 1.0);
  } else if (rain > 0) {
    perStep *= (1 + rain);
  }
  final perDay = perStep * stepsPerDay;

  final days = <double>[
    for (var d = 1; d <= horizonDays; d++) (level + perDay * d).clamp(0.0, 100.0)
  ];

  double? until(double target) {
    if (level <= target) return 0;
    if (perDay >= -0.3) return null; // steady or recovering
    return (level - target) / -perDay;
  }

  final mae = absErr / (readings.length - 1);
  final sample = (readings.length / 24).clamp(0.3, 1.0);
  final confidence = ((1 - mae / 3.0).clamp(0.2, 0.95) * sample).clamp(0.0, 0.95);

  final lookback = (span / 1440).round().clamp(1, 60);
  final String why;
  if (perDay < -0.3) {
    final notes = <String>[];
    if (demand > 0) notes.add('higher demand');
    if (rain > 0) notes.add('some rain expected');
    why = 'Falling about ${(-perDay).toStringAsFixed(1)}% a day over the last '
        '$lookback day${lookback == 1 ? '' : 's'}'
        '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}.';
  } else if (perDay > 0.3) {
    why = 'Recovering about ${perDay.toStringAsFixed(1)}% a day.';
  } else {
    why = 'Steady over the last $lookback day${lookback == 1 ? '' : 's'}.';
  }

  return WaterForecast(
    days: days,
    daysToLow: until(40),
    daysToCritical: until(20),
    daysToEmpty: until(0),
    changePerDay: math.max(-100, perDay),
    confidence: confidence,
    why: why,
  );
}

/// What to do about it, in litres and days. Uses the Sphere humanitarian
/// minimum of 15 litres a person a day, and about 50 litres a day for each
/// head of cattle as a planning figure.
class WaterPlan {
  final int litresPerDay;
  final double daysOfCover; // from stored water
  final int daysToCover; // how long to plan for
  final int shortfallLitres;
  final int bottles; // 25 L bottles to close the gap

  const WaterPlan({
    required this.litresPerDay,
    required this.daysOfCover,
    required this.daysToCover,
    required this.shortfallLitres,
    required this.bottles,
  });
}

const litresPerPersonPerDay = 15;
const litresPerCattlePerDay = 50;
const bottleLitres = 25;

WaterPlan planWater({
  required WaterPrefs prefs,
  required WaterForecast forecast,
  int minimumDays = 3,
}) {
  final perDay = prefs.household * litresPerPersonPerDay + prefs.herd * litresPerCattlePerDay;
  // Plan for the outage we expect, at least a few days, at most two weeks.
  final expected = forecast.daysToCritical ?? forecast.daysToLow ?? 0;
  final daysToCover = math.max(minimumDays, expected.isFinite ? expected.ceil() : minimumDays).clamp(minimumDays, 14);
  final need = perDay * daysToCover;
  final shortfall = math.max(0, need - prefs.tankLitres);
  return WaterPlan(
    litresPerDay: perDay,
    daysOfCover: perDay == 0 ? 0 : prefs.tankLitres / perDay,
    daysToCover: daysToCover,
    shortfallLitres: shortfall,
    bottles: (shortfall / bottleLitres).ceil(),
  );
}
