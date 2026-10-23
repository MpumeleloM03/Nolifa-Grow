import 'dart:math' as math;
import '../crops/crop_models.dart';
import '../weather/weather_models.dart';
import 'farm_models.dart';

/// How a crop uses water, from the FAO-56 irrigation manual: the crop
/// coefficient at the start, middle and end of the season, how deep the roots
/// go, and how much of the soil's water the plant can use before it suffers.
class CropWater {
  final double kcIni, kcMid, kcEnd;
  final double rootM;

  /// Share of the available water the crop can use before it is stressed.
  final double p;
  const CropWater(this.kcIni, this.kcMid, this.kcEnd, this.rootM, this.p);
}

const cropWater = <String, CropWater>{
  'Maize': CropWater(0.30, 1.20, 0.60, 1.0, 0.55),
  'Tomato': CropWater(0.60, 1.15, 0.80, 0.7, 0.40),
  'Spinach': CropWater(0.70, 1.00, 0.95, 0.30, 0.20),
  'Cabbage': CropWater(0.70, 1.05, 0.95, 0.50, 0.45),
  'Carrot': CropWater(0.70, 1.05, 0.95, 0.50, 0.35),
  'Onion': CropWater(0.70, 1.05, 0.75, 0.30, 0.30),
  'Potato': CropWater(0.50, 1.15, 0.75, 0.50, 0.35),
  'Butternut': CropWater(0.50, 1.00, 0.80, 0.80, 0.50),
  'Beans': CropWater(0.40, 1.15, 0.35, 0.50, 0.45),
  'Peppers': CropWater(0.60, 1.05, 0.90, 0.60, 0.30),
  'Sweet potato': CropWater(0.50, 1.15, 0.65, 0.80, 0.65),
};

CropWater waterSpecFor(String crop) => cropWater[crop] ?? cropWater['Tomato']!;

/// The crop coefficient on a day of the cycle ([progress] 0 to 1): flat at the
/// start, rising to the middle value, flat through the middle, then falling.
double kcAt(CropWater c, double progress) {
  final t = progress.clamp(0.0, 1.0);
  if (t < 0.15) return c.kcIni;
  if (t < 0.45) return c.kcIni + (c.kcMid - c.kcIni) * ((t - 0.15) / 0.30);
  if (t < 0.80) return c.kcMid;
  return c.kcMid + (c.kcEnd - c.kcMid) * ((t - 0.80) / 0.20);
}

/// Roots grow with the crop, so the soil reservoir it can reach grows too.
double rootDepthM(CropWater c, double progress) =>
    math.max(0.15, c.rootM * (0.35 + 0.65 * math.min(1.0, progress / 0.5)));

/// Rain that reaches the roots. A shower under 3 mm wets the leaves and
/// evaporates; very heavy rain runs off or drains past the roots.
double effectiveRain(double mm) => mm < 3 ? 0 : 0.8 * math.min(mm, 40);

/// Reference evapotranspiration when the weather source gave none, from the
/// Hargreaves-Samani equation with extraterrestrial radiation for the latitude.
double estimateEt0(double minC, double maxC, double latitude, DateTime date) {
  final lat = latitude * math.pi / 180;
  final doy = date.difference(DateTime(date.year)).inDays + 1;
  final dr = 1 + 0.033 * math.cos(2 * math.pi / 365 * doy);
  final decl = 0.409 * math.sin(2 * math.pi / 365 * doy - 1.39);
  final ws = math.acos((-math.tan(lat) * math.tan(decl)).clamp(-1.0, 1.0));
  final ra = 24 * 60 / math.pi * 0.0820 * dr *
      (ws * math.sin(lat) * math.sin(decl) + math.cos(lat) * math.cos(decl) * math.sin(ws));
  final et = 0.0023 * ((minC + maxC) / 2 + 17.8) * math.sqrt(math.max(0.0, maxC - minC)) * ra * 0.408;
  return math.max(0.5, et);
}

/// What to do with one plot on one day.
enum DayAction {
  water('Water'),
  rainSkip('Skip, rain'),
  rest('Rest');

  final String label;
  const DayAction(this.label);
}

class PlotDay {
  final DateTime date;
  final double et0;
  final double etc; // what the crop uses
  final double rainMm;
  final double effRainMm;
  final DayAction action;
  final double netMm; // water into the soil
  final double litres; // what leaves the pipe
  final int minutes;
  final double depletionEnd; // mm of easy water used up at the end of the day
  final double calendarLitres; // what watering by the calendar every day would use

  /// Litres a calendar schedule would still have pumped that the rain does for
  /// free today. Water held back only to be used later is not counted.
  final double rainWorkLitres;
  const PlotDay({
    required this.date,
    required this.et0,
    required this.etc,
    required this.rainMm,
    required this.effRainMm,
    required this.action,
    required this.netMm,
    required this.litres,
    required this.minutes,
    required this.depletionEnd,
    required this.calendarLitres,
    required this.rainWorkLitres,
  });
}

class PlotPlan {
  final CropPlot plot;
  final IrrigationSystem? system;
  final double tawMm; // total water the roots can reach in this soil
  final double rawMm; // the share the crop can use before it suffers
  final double depletionNowMm;
  final double kc;
  final List<PlotDay> days;
  final double confidence; // 0 to 1
  final bool realWeather;
  final List<String> why;
  const PlotPlan({
    required this.plot,
    required this.system,
    required this.tawMm,
    required this.rawMm,
    required this.depletionNowMm,
    required this.kc,
    required this.days,
    required this.confidence,
    required this.realWeather,
    required this.why,
  });

  PlotDay get today => days.first;

  PlotDay? get nextWater {
    for (final d in days) {
      if (d.action == DayAction.water) return d;
    }
    return null;
  }

  double get weekLitres => days.fold(0.0, (a, d) => a + d.litres);
  double get weekCalendarLitres => days.fold(0.0, (a, d) => a + d.calendarLitres);
  double get weekRainWorkLitres => days.fold(0.0, (a, d) => a + d.rainWorkLitres);

  /// How full the easy-water bucket is right now, 0 to 1.
  double get soilFullness => rawMm == 0 ? 1 : (1 - depletionNowMm / rawMm).clamp(0.0, 1.0);

  String get confidenceLabel => confidence >= 0.75 ? 'High' : confidence >= 0.5 ? 'Medium' : 'Low';
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Works out when and how much to water one plot over the next seven days.
///
/// The method is the FAO-56 soil water balance: a bucket of water the roots can
/// reach, drained each day by what the crop uses (crop coefficient times
/// reference evapotranspiration) and refilled by effective rain and watering.
/// The plot is watered only when the bucket would run past what the crop can
/// stand losing. It is a rule-based model, not a neural network, and it says
/// how sure it is.
PlotPlan planPlot({
  required CropPlot plot,
  required FarmProfile farm,
  required Forecast forecast,
  required DateTime now,
  required double latitude,
}) {
  final today = _midnight(now);
  final spec = waterSpecFor(plot.crop);
  final system = farm.systemFor(plot.id);
  final eff = system?.efficiency ?? 0.75;
  final cycle = plot.spec.daysToHarvest;

  double progressOn(DateTime d) => (d.difference(plot.plantedOn).inDays / cycle).clamp(0.0, 1.0);
  double et0Of(DayForecast d) => d.et0 ?? estimateEt0(d.minC, d.maxC, latitude, d.date);

  final progress = progressOn(today);
  final taw = farm.soil.mmPerMetre * rootDepthM(spec, progress);
  final raw = spec.p * taw;

  // Walk the last few days to find how much water the soil has already lost.
  var dr = 0.5 * raw; // no sensor, so assume half the easy water is gone
  final myChecks = [for (final c in farm.soilChecks) if (c.plotId == plot.id) c];
  final myRuns = [for (final r in farm.runs) if (r.plotId == plot.id) r];
  final area = math.max(1.0, plot.areaM2);

  double applyEvents(double dr, DateTime day) {
    for (final r in myRuns) {
      if (_midnight(r.at) == day) dr -= r.litres * eff / area;
    }
    for (final c in myChecks) {
      if (_midnight(c.at) == day) {
        dr = switch (c.feel) {
          SoilFeel.dry => raw,
          SoilFeel.ok => 0.4 * raw,
          SoilFeel.wet => 0,
        };
      }
    }
    return dr.clamp(0.0, taw);
  }

  for (final d in forecast.past) {
    final day = _midnight(d.date);
    if (!day.isBefore(today)) continue;
    final kc = kcAt(spec, progressOn(day));
    dr = (dr + kc * et0Of(d) - effectiveRain(d.rainMm)).clamp(0.0, taw);
    dr = applyEvents(dr, day);
  }
  dr = applyEvents(dr, today); // something done earlier today
  final depletionNow = dr;

  // Look ahead seven days.
  final rows = <PlotDay>[];
  final forecastDays = forecast.days.take(7).toList();
  final tomorrowRain = <double>[
    for (var i = 0; i < forecastDays.length; i++)
      i + 1 < forecastDays.length ? effectiveRain(forecastDays[i + 1].rainMm) : 0.0
  ];
  var kcToday = kcAt(spec, progress);
  for (var i = 0; i < forecastDays.length; i++) {
    final f = forecastDays[i];
    final day = _midnight(f.date);
    final kc = kcAt(spec, progressOn(day));
    if (i == 0) kcToday = kc;
    final et0 = et0Of(f);
    final etc = kc * et0;
    final peff = effectiveRain(f.rainMm);
    final withRain = (dr + etc - peff).clamp(0.0, taw);
    final noRain = dr + etc;
    var action = DayAction.rest;
    var net = 0.0;
    var after = withRain;

    final needsWater = withRain >= raw;
    final rainTomorrowRescues = needsWater && i + 1 < forecastDays.length && withRain < taw * 0.9 && withRain - tomorrowRain[i] < raw * 0.6;
    if (needsWater && !rainTomorrowRescues) {
      action = DayAction.water;
      // Refill the easy water, but in one go no more than the crop can use before it
      // suffers (with a ceiling), because more than that drains past the roots.
      net = withRain.clamp(6.0, math.min(40.0, math.max(10.0, raw * 1.2)));
      after = math.max(0.0, withRain - net);
    } else if (rainTomorrowRescues || (noRain >= raw && withRain < raw)) {
      action = DayAction.rainSkip;
    }
    final litres = action == DayAction.water ? net / eff * area : 0.0;
    final flow = system == null ? 0.0 : system.flowLph / 60;
    rows.add(PlotDay(
      date: day,
      et0: et0,
      etc: etc,
      rainMm: f.rainMm,
      effRainMm: peff,
      action: action,
      netMm: net,
      litres: litres,
      minutes: flow > 0 && litres > 0 ? (litres / flow).ceil() : 0,
      depletionEnd: after,
      calendarLitres: etc / eff * area,
      rainWorkLitres: math.min(peff, etc) / eff * area,
    ));
    dr = after;
  }

  // How sure are we?
  final real = !forecast.demo && !forecast.saved;
  final recentTouch = [
    ...myChecks.map((c) => c.at),
    ...myRuns.map((r) => r.at),
  ].any((t) => now.difference(t).inDays <= 3);
  var confidence = 0.35;
  if (real) confidence += 0.2;
  if (forecast.past.isNotEmpty) confidence += 0.1;
  if (recentTouch) confidence += 0.25;
  if (system != null) confidence += 0.1;
  confidence = confidence.clamp(0.0, 1.0);

  final why = <String>[];
  final t0 = rows.isEmpty ? null : rows.first;
  if (t0 != null) {
    why.add('${plot.crop} uses ${t0.etc.toStringAsFixed(1)} mm today (crop factor ${kcToday.toStringAsFixed(2)} times ${t0.et0.toStringAsFixed(1)} mm that the weather evaporates).');
    why.add('The roots reach ${(rootDepthM(spec, progress) * 100).round()} cm of ${farm.soil.label.toLowerCase()} soil. '
        'It holds ${taw.round()} mm and the crop can use ${raw.round()} mm before it suffers. '
        'About ${depletionNow.round()} mm is used now.');
    final nw = rows.where((d) => d.action == DayAction.water).firstOrNull;
    final rs = rows.where((d) => d.action == DayAction.rainSkip).firstOrNull;
    if (nw == null) {
      why.add(rs != null
          ? 'No watering needed this week: ${rs.effRainMm.round()} mm of useful rain is expected.'
          : 'No watering needed this week: the soil holds enough.');
    } else {
      why.add('The soil runs out of easy water ${_dayWord(nw.date, today)}. Apply ${nw.netMm.round()} mm.');
    }
  }
  if (!real) why.add(forecast.demo ? 'This uses a demo forecast.' : 'This uses the last saved forecast because there is no signal.');
  if (!recentTouch) why.add('Feel the soil and tell the app to sharpen this. Without a check it assumes the soil is half used.');

  return PlotPlan(
    plot: plot,
    system: system,
    tawMm: taw,
    rawMm: raw,
    depletionNowMm: depletionNow,
    kc: kcToday,
    days: rows,
    confidence: confidence,
    realWeather: real,
    why: why,
  );
}

/// "25 min", "2 h", "8 h 24 min".
String durationText(int minutes) {
  if (minutes < 90) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String _dayWord(DateTime d, DateTime today) {
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return 'on ${names[d.weekday - 1]}';
}

/// A tank's days of water at the rate the plans will use it. Null if nothing
/// will be drawn from it this week.
double? tankDays(WaterSource tank, double litresPerWeek) {
  if (litresPerWeek <= 0) return null;
  return tank.levelL / (litresPerWeek / 7);
}

/// The farm-wide picture: plans for every plot, and whether the water lasts.
class FarmIrrigation {
  final List<PlotPlan> plans;
  const FarmIrrigation(this.plans);

  double get weekLitres => plans.fold(0.0, (a, p) => a + p.weekLitres);
  double get weekCalendarLitres => plans.fold(0.0, (a, p) => a + p.weekCalendarLitres);
  double get weekRainWorkLitres => plans.fold(0.0, (a, p) => a + p.weekRainWorkLitres);

  /// Share of a calendar schedule's water that the rain does instead. This is
  /// the only saving counted: water held back now but needed next week is just
  /// a delay.
  double get savedPct => weekCalendarLitres <= 0 ? 0 : (weekRainWorkLitres / weekCalendarLitres).clamp(0.0, 1.0);
  List<PlotPlan> get wateringToday => [for (final p in plans) if (p.today.action == DayAction.water) p];
}

FarmIrrigation planFarm({
  required List<CropPlot> plots,
  required FarmProfile farm,
  required Forecast forecast,
  required DateTime now,
  required double latitude,
}) =>
    FarmIrrigation([
      for (final p in plots) planPlot(plot: p, farm: farm, forecast: forecast, now: now, latitude: latitude)
    ]);

/// Litres drawn from [source] by the plans this week.
double weekDrawFrom(WaterSource source, FarmProfile farm, FarmIrrigation plan) {
  var total = 0.0;
  for (final p in plan.plans) {
    final s = p.system;
    if (s != null && s.sourceId == source.id) total += p.weekLitres;
  }
  return total;
}
