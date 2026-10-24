import '../crops/crop_models.dart';
import 'weather_models.dart';

/// A weather threat to the farm in the next week, with what to do about it.
class WeatherThreat {
  final String kind; // frost | heat | heavyRain | drySpell | wind
  final String severity; // 'orange' watch or 'red' urgent
  final DateTime on;
  final String title;
  final String body;
  final List<String> actions;
  final List<String> plots; // names of the plots it affects
  const WeatherThreat(this.kind, this.severity, this.on, this.title, this.body, this.actions, this.plots);

  bool get urgent => severity == 'red';
  String get emoji => switch (kind) {
        'frost' => '🥶',
        'heat' => '🔥',
        'heavyRain' => '🌧️',
        'drySpell' => '🏜️',
        'cold' => '🥶',
        _ => '💨',
      };
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String dayName(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(now.year, now.month, now.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// Crops that a frost burns or kills.
const frostTender = {'Tomato', 'Beans', 'Peppers', 'Butternut', 'Sweet potato', 'Maize'};

/// Crops that suffer in extreme heat.
const heatSensitive = {'Spinach', 'Cabbage', 'Tomato', 'Peppers', 'Beans'};

/// Crops that rot or catch fungus when it is very wet.
const wetSensitive = {'Tomato', 'Potato', 'Carrot', 'Onion', 'Cabbage'};

/// Turns a forecast into the threats a farmer should act on, most urgent and
/// soonest first. Thresholds: frost at 2 C or less (0 C is a hard frost), heat
/// at 35 C, heavy rain at 30 mm in a day or 60 mm over three, a dry spell is
/// under 3 mm in a week with hot days, wind at 50 km/h.
List<WeatherThreat> assessWeather(Forecast f, List<CropPlot> plots, DateTime now,
    {int animals = 0, bool humidCoast = false}) {
  final out = <WeatherThreat>[];
  List<String> affected(Set<String> sensitive) =>
      [for (final p in plots) if (sensitive.contains(p.crop)) p.name];

  // Frost
  for (final d in f.days) {
    if (d.minC <= 2) {
      final hard = d.minC <= 0;
      final who = affected(frostTender);
      out.add(WeatherThreat(
        'frost',
        hard ? 'red' : 'orange',
        d.date,
        hard ? 'Hard frost ${dayName(d.date, now)}' : 'Frost risk ${dayName(d.date, now)}',
        'Lowest ${d.minC.toStringAsFixed(1)} C. Tender crops can be burned in one night.',
        [
          'Cover tender plants with cloth or plastic before sunset',
          'Water the soil in the afternoon. Wet soil holds heat through the night',
          'Harvest what is nearly ready. Sell it fast on Nolifa Drop as a rescue deal',
        ],
        who,
      ));
      break; // the first frost night is the one to prepare for
    }
  }

  // Heat
  for (final d in f.days) {
    if (d.maxC >= 35) {
      out.add(WeatherThreat(
        'heat',
        d.maxC >= 38 ? 'red' : 'orange',
        d.date,
        'Heat ${dayName(d.date, now)}',
        'Up to ${d.maxC.toStringAsFixed(0)} C. Plants wilt and flowers drop.',
        [
          'Water early morning and late evening, not midday',
          'Mulch the soil and shade young plants',
          'Give cattle shade and extra water',
        ],
        affected(heatSensitive),
      ));
      break;
    }
  }

  // Heavy rain
  for (var i = 0; i < f.days.length; i++) {
    final d = f.days[i];
    final three = f.days.skip(i).take(3).fold<double>(0, (a, x) => a + x.rainMm);
    if (d.rainMm >= 30 || three >= 60) {
      out.add(WeatherThreat(
        'heavyRain',
        d.rainMm >= 50 ? 'red' : 'orange',
        d.date,
        'Heavy rain ${dayName(d.date, now)}',
        '${d.rainMm.toStringAsFixed(0)} mm expected${three > d.rainMm ? ', about ${three.toStringAsFixed(0)} mm over three days' : ''}. Waterlogging and blight follow.',
        [
          'Clear drains and furrows so water leaves the field',
          'Skip sprinkler runs until the ground dries',
          'Spray a protective fungicide on tomatoes and potatoes before it starts',
        ],
        affected(wetSensitive),
      ));
      break;
    }
  }

  // Livestock. Humid coastal air (Greater Durban, the North and South Coast)
  // makes cattle suffer from about 29 C, so the bar is lower there.
  if (animals > 0) {
    final heatAt = humidCoast ? 29.0 : 32.0;
    for (final d in f.days) {
      if (d.maxC >= heatAt) {
        out.add(WeatherThreat(
          'heat',
          d.maxC >= heatAt + 4 ? 'red' : 'orange',
          d.date,
          'Heat stress for your herd ${dayName(d.date, now)}',
          'Up to ${d.maxC.toStringAsFixed(0)} C${humidCoast ? ' with coastal humidity' : ''}. Animals eat less, drink far more and can collapse.',
          [
            'Fill every trough and check the water twice, not once',
            'Give shade, and move animals off open ground from 11:00 to 16:00',
            'Feed in the cool of early morning and evening',
            'Watch for panting, drooling or animals standing apart, and call a vet early',
          ],
          const [],
        ));
        break;
      }
    }
    for (final d in f.days) {
      if (d.minC <= 7 && d.rainMm >= 8) {
        out.add(WeatherThreat(
          'cold',
          d.minC <= 3 ? 'red' : 'orange',
          d.date,
          'Cold and wet for young animals ${dayName(d.date, now)}',
          'Low of ${d.minC.toStringAsFixed(0)} C with ${d.rainMm.toStringAsFixed(0)} mm of rain. Calves, lambs and kids chill fast.',
          ['Shelter young and weak animals out of the wind and wet', 'Give extra feed, they burn more energy to stay warm', 'Dry bedding, and check newborns at night'],
          const [],
        ));
        break;
      }
    }
  }

  // Dry spell
  final totalRain = f.days.fold<double>(0, (a, x) => a + x.rainMm);
  final hot = f.days.where((d) => d.maxC >= 30).length;
  if (f.days.length >= 5 && totalRain < 3 && hot >= 3) {
    out.add(WeatherThreat(
      'drySpell',
      'orange',
      f.days.first.date,
      'Dry week ahead',
      'Under ${totalRain < 1 ? '1' : '3'} mm of rain and $hot hot days.',
      [
        'Check your water tank and plan sprinkler runs',
        'Add a few minutes to each run for thirsty crops',
        'Watch the water radar for your community',
      ],
      [for (final p in plots) p.name],
    ));
  }

  // Wind
  for (final d in f.days) {
    if (d.windKmh >= 50) {
      out.add(WeatherThreat(
        'wind',
        d.windKmh >= 70 ? 'red' : 'orange',
        d.date,
        'Strong wind ${dayName(d.date, now)}',
        'Gusts up to ${d.windKmh.toStringAsFixed(0)} km/h. Tall crops like maize can lodge.',
        ['Stake tall plants', 'Secure netting and shade cloth', 'Move animals out of open ground'],
        [for (final p in plots) if (p.crop == 'Maize' || p.crop == 'Tomato') p.name],
      ));
      break;
    }
  }

  out.sort((a, b) {
    final s = (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0);
    return s != 0 ? s : a.on.compareTo(b.on);
  });
  return out;
}

/// What the forecast means for one plot's sprinkler: skip a run when real rain
/// is coming, add one in a hot dry spell. Null when nothing needs changing.
String? sprinklerAdvice(Forecast f, CropPlot plot, DateTime now) {
  if (!plot.sprinkler.enabled || f.days.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  for (final d in f.days.take(2)) {
    if (d.rainMm >= 5 && d.rainChance >= 60) {
      final when = dayName(d.date, now);
      final saved = (plot.sprinkler.litresPerDay * (d.date.difference(today).inDays == 0 ? 0.5 : 1)).round();
      return 'Rain on the way ($when, about ${d.rainMm.toStringAsFixed(0)} mm). Skip the sprinkler run and save about $saved litres.';
    }
  }
  final next3 = f.days.take(3).toList();
  if (next3.length == 3 && next3.every((d) => d.maxC >= 33) && next3.fold<double>(0, (a, d) => a + d.rainMm) < 1) {
    return 'Hot and dry for three days. Add a short extra run in the evening.';
  }
  return null;
}
