import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' hide Text;
import '../theme/app_theme.dart';
import 'water_models.dart';

import '../tr_text.dart' show Text;
import '../tr.dart' show tr, trn;
// Small pieces shared by the water page and the provider desk. Nothing here
// reads state: every widget takes what it shows, so each can be tested alone.

/// "2 h ago" style freshness, so a stale reading is never mistaken for a live one.
String agoText(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "14:32" for today, "20 Oct 14:32" for an earlier day: the real time a stage was reached.
String clockText(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = t.year == n.year && t.month == n.month && t.day == n.day;
  return today ? hm : '${t.day} ${_months[t.month - 1]} $hm';
}

/// 85000 becomes "85 000", the way South Africans write it.
String groupDigits(num v) =>
    v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// "1 truck", "3 trucks".
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// A span of days a person can read at a glance: "4.6 days", "12 days", "less than a day".
String daysText(double d) {
  if (d < 1) return 'less than a day';
  final r = d < 10 ? (d * 10).round() / 10 : d.roundToDouble();
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return '$s ${r == 1 ? 'day' : 'days'}';
}

/// The radar's one-line answer: how long until the supply is Critical.
String forecastHeadline(WaterForecast f) {
  if (f.confidence <= 0) return 'Not enough readings yet';
  final critical = f.daysToCritical;
  if (critical == null) return f.changePerDay > 0.3 ? 'Recovering' : 'Steady';
  if (critical <= 0) {
    final empty = f.daysToEmpty;
    if (empty == null || empty <= 0) return 'Critical now';
    return empty < 1 ? 'Under a day until empty' : 'About ${daysText(empty)} until empty';
  }
  return critical < 1 ? 'Under a day until Critical' : 'About ${daysText(critical)} until Critical';
}

/// How urgent the forecast reads: green when steady, red when Critical is near.
Color forecastColor(WaterForecast f) {
  if (f.confidence <= 0) return AppTheme.textSecondary;
  final critical = f.daysToCritical;
  if (critical == null) return AppTheme.ok;
  if (critical < 3) return AppTheme.danger;
  if (critical < 7) return AppTheme.warn;
  return AppTheme.ok;
}

/// A community's newest incident whatever its stage, so a just-resolved
/// request can still be shown.
WaterIncident? newestIncident(Iterable<WaterIncident> all, String zoneId) {
  WaterIncident? best;
  for (final i in all) {
    if (i.zoneId == zoneId && (best == null || i.epoch > best.epoch)) best = i;
  }
  return best;
}

/// The bar that holds a bottom sheet's content, lifted above the keyboard.
class WaterSheet extends StatelessWidget {
  final Widget child;
  const WaterSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.sheet,
            borderRadius: const BorderRadius.vertical(top: const Radius.circular(AppTheme.rCard)),
          ),
          padding: const EdgeInsets.all(AppTheme.s6),
          child: SafeArea(top: false, child: SingleChildScrollView(child: child)),
        ),
      );
}

/// Back arrow row that sits above a pushed water screen.
class WaterBackRow extends StatelessWidget {
  const WaterBackRow({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppTheme.s2, AppTheme.s2, AppTheme.s6, 0),
        child: Row(children: [
          IconButton(
            tooltip: tr('Back'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ]),
      );
}

/// A selectable pill: a community, a quick amount.
class WaterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  const WaterChip({super.key, required this.label, required this.selected, required this.onTap, this.dot});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.rControl);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s2),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: selected ? AppTheme.sprout.withValues(alpha: 0.18) : AppTheme.glassFill,
              border: Border.all(color: selected ? AppTheme.sprout : AppTheme.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: AppTheme.subhead.copyWith(
                    color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A value with minus and plus buttons. [subject] names what changes, for
/// screen readers: "Decrease people".
class AmountStepper extends StatelessWidget {
  final String value;
  final String subject;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const AmountStepper({super.key, required this.value, required this.subject, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.glassFillStrong,
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.sprout.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: tr('Decrease $subject'),
            visualDensity: VisualDensity.compact,
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Text(value, textAlign: TextAlign.center, style: AppTheme.headline),
          ),
          IconButton(
            tooltip: tr('Increase $subject'),
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ]),
      );
}

/// A small label over a value, for the numbers people compare.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatTile({super.key, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppTheme.s3),
        decoration: BoxDecoration(
          color: AppTheme.glassFill,
          borderRadius: BorderRadius.circular(AppTheme.rChip + 4),
          border: Border.all(color: AppTheme.glassBorderSoft),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 2),
          Text(value, style: AppTheme.headline.copyWith(color: color)),
        ]),
      );
}

/// How much to trust a forecast, as a bar and a word. Honest about low values.
class ConfidenceMeter extends StatelessWidget {
  final double value; // 0..1
  const ConfidenceMeter({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 0.7 ? AppTheme.ok : (value >= 0.4 ? AppTheme.warn : AppTheme.danger);
    final word = value <= 0 ? 'None yet' : (value >= 0.7 ? 'High' : (value >= 0.4 ? 'Fair' : 'Low'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Confidence', style: AppTheme.footnote),
        const Spacer(),
        Text('${(value * 100).round()}%  •  $word', style: AppTheme.footnote.copyWith(color: color)),
      ]),
      const SizedBox(height: AppTheme.s2),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Stack(fit: StackFit.expand, children: [
              ColoredBox(color: AppTheme.glassFillStrong),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: ColoredBox(color: color),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Seven days ahead, one bar a day, with the Low and Critical lines marked.
///
/// The first bar is the reservoir now; the rest are the radar's forecast.
class WaterRadarChart extends StatelessWidget {
  final double now; // current level, 0..100
  final List<double> days; // forecast level at the end of each coming day
  final DateTime? today; // fixes the day labels in tests
  const WaterRadarChart({super.key, required this.now, required this.days, this.today});

  @override
  Widget build(BuildContext context) {
    final values = [now, ...days];
    final start = today ?? DateTime.now();
    return Semantics(
      label: 'Forecast chart. Reservoir at ${now.round()} percent now, '
          'about ${days.last.round()} percent in ${days.length} days.',
      child: SizedBox(
        height: 176,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1300),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => CustomPaint(painter: _RadarPainter(values, start, t)),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values;
  final DateTime start;
  final double t;
  _RadarPainter(this.values, this.start, this.t);

  static const _gutter = 74.0; // room for the Low and Critical labels
  static const _top = 18.0;
  static const _bottom = 22.0;
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  void _text(Canvas c, String s, double x, double y, TextStyle style, {TextAlign align = TextAlign.left, double width = 60}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    final dx = switch (align) {
      TextAlign.center => x - tp.width / 2,
      TextAlign.right => x - tp.width,
      _ => x,
    };
    tp.paint(c, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - _top - _bottom;
    final plotW = size.width - _gutter;
    final base = _top + plotH;
    // Zoom the axis to the data, but never below 60 so the Low line always shows.
    final peak = values.reduce(math.max);
    final axisMax = math.min(100.0, math.max(60.0, ((peak + 10) / 20).ceil() * 20.0));
    double yOf(double level) => base - plotH * (level / axisMax).clamp(0.0, 1.0);
    final small = AppTheme.caption.copyWith(fontSize: 10);

    final n = values.length;
    final slot = plotW / n;
    final barW = math.min(slot * 0.56, 22.0);
    for (var i = 0; i < n; i++) {
      // Each bar grows a beat after the one before it.
      final p = Curves.easeOutCubic.transform((t * (n + 3) - i).clamp(0.0, 1.0));
      final h = (base - yOf(values[i])) * p;
      final x = _gutter + slot * i + (slot - barW) / 2;
      final color = WaterStatusX.of(values[i]).color;
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(x, base - h, x + barW, base,
            topLeft: const Radius.circular(6), topRight: const Radius.circular(6)),
        Paint()..color = color.withValues(alpha: i == 0 ? 1 : 0.55),
      );
      if (p > 0.6) {
        _text(canvas, '${values[i].round()}', x + barW / 2, base - h - 14, small, align: TextAlign.center, width: slot);
      }
      final label = i == 0 ? 'Now' : _dayNames[(start.weekday - 1 + i) % 7];
      _text(canvas, label, x + barW / 2, base + 6, small.copyWith(color: i == 0 ? AppTheme.textPrimary : null),
          align: TextAlign.center, width: slot);
    }

    for (final (level, label, color) in [
      (40.0, 'Low 40%', WaterStatus.low.color),
      (20.0, 'Critical 20%', WaterStatus.critical.color),
    ]) {
      final y = yOf(level);
      final line = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = _gutter; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), line);
      }
      _text(canvas, label, _gutter - 6, y - 6, small.copyWith(color: color), align: TextAlign.right, width: _gutter - 6);
    }
    canvas.drawLine(Offset(_gutter, base), Offset(size.width, base),
        Paint()..color = AppTheme.glassBorder);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.t != t || old.start != start || !listEquals(old.values, values);
}

/// The five stages of a request, with a tick and the real time for each one reached.
class IncidentTimeline extends StatelessWidget {
  final WaterIncident? incident; // null before anyone has asked
  const IncidentTimeline({super.key, required this.incident});

  DateTime? _at(IncidentStage s) => switch (s) {
        IncidentStage.open => incident?.openedAt,
        IncidentStage.requested => incident?.requestedAt,
        IncidentStage.acknowledged => incident?.acknowledgedAt,
        IncidentStage.dispatched => incident?.dispatchedAt,
        IncidentStage.resolved => incident?.resolvedAt,
      };

  @override
  Widget build(BuildContext context) {
    final reached = incident?.stage.index ?? -1;
    const stages = IncidentStage.values;
    return Column(children: [
      for (final s in stages)
        _TimelineStep(
          key: ValueKey('stage-${s.name}'),
          stage: s,
          done: s.index <= reached,
          current: s.index == reached,
          last: s == stages.last,
          at: s.index <= reached ? _at(s) : null,
        ),
    ]);
  }
}

class _TimelineStep extends StatelessWidget {
  final IncidentStage stage;
  final bool done;
  final bool current;
  final bool last;
  final DateTime? at;
  const _TimelineStep({
    super.key,
    required this.stage,
    required this.done,
    required this.current,
    required this.last,
    required this.at,
  });

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22, color: done ? AppTheme.sprout : AppTheme.textTertiary),
            if (!last)
              Container(width: 2, height: 18, color: done ? AppTheme.sprout.withValues(alpha: 0.5) : AppTheme.glassBorder),
          ]),
        ),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(stage.label,
                style: (current ? AppTheme.headline : AppTheme.subhead)
                    .copyWith(color: current ? AppTheme.sprout : (done ? AppTheme.textPrimary : AppTheme.textTertiary))),
          ),
        ),
        if (at != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(clockText(at!), style: AppTheme.footnote)),
      ]);
}
