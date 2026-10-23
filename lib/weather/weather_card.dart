import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'weather_models.dart';
import 'weather_service.dart';
import 'weather_threats.dart';

const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _icon(DayForecast d) {
  if (d.rainMm >= 20) return '🌧️';
  if (d.rainMm >= 5 && d.rainChance >= 50) return '🌦️';
  if (d.minC <= 2) return '🥶';
  if (d.maxC >= 35) return '🔥';
  return d.maxC >= 25 ? '☀️' : '⛅';
}

/// A threat with what to do about it.
class ThreatCard extends StatelessWidget {
  final WeatherThreat t;
  const ThreatCard(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = t.urgent ? AppTheme.danger : AppTheme.warn;
    return GlassCard(
      tint: color.withValues(alpha: 0.12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text(t.title, style: AppTheme.headline)),
          Pill(t.urgent ? 'Urgent' : 'Watch', color: color),
        ]),
        const SizedBox(height: AppTheme.s1),
        Text(t.body, style: AppTheme.callout),
        if (t.plots.isNotEmpty) ...[
          const SizedBox(height: AppTheme.s2),
          Text('Your plots at risk: ${t.plots.join(', ')}',
              style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: AppTheme.s2),
        for (final a in t.actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: AppTheme.footnote),
              Expanded(child: Text(a, style: AppTheme.footnote)),
            ]),
          ),
      ]),
    );
  }
}

/// The week ahead, with the biggest threat in plain words.
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(forecastProvider);
    final threats = ref.watch(weatherThreatsProvider);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: async.when(
        loading: () => Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.sprout)),
          const SizedBox(width: AppTheme.s3),
          Text('Getting the forecast', style: AppTheme.callout),
        ]),
        error: (_, __) => Text('Forecast not available right now.', style: AppTheme.callout),
        data: (f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🌤️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: AppTheme.s2),
            Expanded(child: Text('Weather, ${f.region}', style: AppTheme.headline)),
            if (f.demo) Pill('Demo forecast', color: AppTheme.warn)
            else if (f.saved) Pill('Saved forecast', color: AppTheme.textSecondary),
          ]),
          const SizedBox(height: AppTheme.s2),
          Text(
              threats.isEmpty ? 'No weather threats this week.' : '${threats.first.emoji} ${threats.first.title}. ${threats.length > 1 ? '${threats.length - 1} more in the alarm.' : 'Details in the alarm.'}',
              style: AppTheme.subhead.copyWith(
                  color: threats.isEmpty ? AppTheme.ok : (threats.first.urgent ? AppTheme.danger : AppTheme.warn),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            for (final d in f.days.take(7))
              Expanded(
                child: Column(children: [
                  Text(_short[d.date.weekday - 1], style: AppTheme.caption),
                  Text(_icon(d), style: const TextStyle(fontSize: 18)),
                  Text('${d.maxC.round()}', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
                  Text('${d.minC.round()}', style: AppTheme.caption),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}
