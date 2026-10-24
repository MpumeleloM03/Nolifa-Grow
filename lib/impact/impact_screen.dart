import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill, SectionTitle;
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'impact_models.dart';
import 'impact_store.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
String pct(double v) => '${(v * 100).round()}%';

/// "Was this right?" under a diagnosis. The farmer sees the plant or animal
/// with their own eyes, so their answer is the closest thing to ground truth
/// the app can get on a phone.
class FeedbackBar extends ConsumerWidget {
  final String id;
  final String kind;
  final String label;
  final String plainName;
  final String confidence;
  const FeedbackBar({
    super.key,
    required this.id,
    required this.kind,
    required this.label,
    required this.plainName,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final given = ref.watch(impactStoreProvider.select((d) {
      for (final s in d.scans) {
        if (s.id == id) return s.verdict;
      }
      return null;
    }));
    void rate(Verdict v) => ref.read(impactStoreProvider.notifier).rateScan(ScanFeedback(
        id, DateTime.now(), kind, label, plainName, double.tryParse(confidence.replaceAll('%', '')) ?? 0, v));

    Widget choice(Verdict v, String text, IconData icon) {
      final on = given == v;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: on ? AppTheme.sprout.withValues(alpha: 0.22) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              side: BorderSide(color: on ? AppTheme.sprout : const Color(0xFF9AA79F), width: 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              onTap: () => rate(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(children: [
                  Icon(icon, size: 20, color: on ? AppTheme.sprout : const Color(0xFF5E6B63)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF33413A))),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Was this right?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
      const SizedBox(height: 2),
      const Text('Your answer builds the accuracy score on the Impact page.',
          style: TextStyle(fontSize: 12, color: Colors.black45)),
      const SizedBox(height: 8),
      Row(children: [
        choice(Verdict.right, 'Yes, right', Icons.check_circle_outline_rounded),
        choice(Verdict.wrong, 'No, wrong', Icons.cancel_outlined),
        choice(Verdict.unsure, 'Not sure', Icons.help_outline_rounded),
      ]),
      if (given != null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Saved. Thank you.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
    ]);
  }
}

/// What the app can prove about itself, with how many cases each number rests
/// on and how wide the doubt around it is.
class ImpactScreen extends ConsumerStatefulWidget {
  const ImpactScreen({super.key});

  @override
  ConsumerState<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends ConsumerState<ImpactScreen> {
  String? _settleNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  Future<void> _settle() async {
    final region = ref.read(currentUserProvider)?.region;
    final n = await ref
        .read(impactStoreProvider.notifier)
        .settleForecasts((region == null || region.isEmpty) ? 'Greater Durban' : region, DateTime.now());
    if (mounted && n > 0) setState(() => _settleNote = 'Checked $n forecast days against the weather that happened.');
  }

  @override
  Widget build(BuildContext context) {
    final sample = ref.watch(impactSampleProvider);
    final real = ref.watch(impactStoreProvider);
    final data = sample ? sampleImpact(DateTime.now()) : real;
    final s = ImpactSummary.of(data);

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.plantAccent,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Impact'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('What we can prove', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text(
                      'Every number here is measured on this phone from your own answers and real weather. '
                      'Each one shows how many cases it rests on. Small samples are marked, not hidden.',
                      style: AppTheme.callout),
                  const SizedBox(height: AppTheme.s4),
                  if (sample)
                    GlassCard(
                      tint: AppTheme.warn.withValues(alpha: 0.18),
                      child: Row(children: [
                        Icon(Icons.science_rounded, color: AppTheme.warn),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                            child: Text('SAMPLE DATA for a demonstration. Not real results. Nothing here is saved.',
                                style: AppTheme.subhead)),
                      ]),
                    ),
                  if (_settleNote != null)
                    Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(_settleNote!, style: AppTheme.footnote)),
                  SectionTitle('🔍', 'Diagnosis accuracy', trailing: _claim(s.scanAccuracy)),
                  _ScanCard(s),
                  SectionTitle('🌦️', 'Weather forecast check', trailing: _claim(s.rainCalls)),
                  _ForecastCard(s),
                  SectionTitle('💧', 'Water saved'),
                  _SavedCard(s, data),
                  SectionTitle('🌾', 'Harvest date accuracy'),
                  _HarvestCard(s, data),
                  SectionTitle('📤', 'Take it with you'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Copy every recorded event as a spreadsheet file (CSV) to send to a mentor, funder or extension officer.',
                          style: AppTheme.callout),
                      const SizedBox(height: AppTheme.s3),
                      GlassButton(
                        label: 'Copy evidence as CSV',
                        icon: Icons.copy_rounded,
                        onPressed: data.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: impactCsv(data)));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Copied. Paste it into a spreadsheet or message.')));
                              },
                      ),
                      const SizedBox(height: AppTheme.s2),
                      GlassButton(
                        label: sample ? 'Show my real numbers' : 'Show a labelled sample',
                        icon: sample ? Icons.person_rounded : Icons.science_rounded,
                        accent: AppTheme.warn,
                        onPressed: () => ref.read(impactSampleProvider.notifier).state = !sample,
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppTheme.s4),
                  Text(
                      'Honest limits: a farmer\'s verdict is an opinion, not a lab test. Forecast checks use Open-Meteo '
                      'observations for the region, not a weather station on your farm. Litres saved count only rain that did the work of a run '
                      'you confirmed you skipped. Below $minSampleToClaim cases we say "too few to claim".',
                      style: AppTheme.footnote),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _claim(Rate r) => r.n == 0
      ? const SizedBox.shrink()
      : Pill(r.claimable ? 'n = ${r.n}' : 'n = ${r.n}, too few to claim',
          color: r.claimable ? AppTheme.ok : AppTheme.warn);
}

class _Stat extends StatelessWidget {
  final String big;
  final String small;
  final Color? color;
  const _Stat(this.big, this.small, {this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(big, style: AppTheme.title2.copyWith(color: color)),
          Text(small, style: AppTheme.caption),
        ]),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => GlassCard(child: Text(text, style: AppTheme.callout));
}

String _range(Rate r) {
  final (lo, hi) = r.interval;
  return '${pct(lo)} to ${pct(hi)}';
}

class _ScanCard extends StatelessWidget {
  final ImpactSummary s;
  const _ScanCard(this.s);

  @override
  Widget build(BuildContext context) {
    final a = s.scanAccuracy;
    if (a.n == 0) {
      return const _Empty('No answers yet. After a scan, tap Yes, No or Not sure under the result. '
          'That is how the app learns whether it is right in your fields.');
    }
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Stat(pct(a.value!), 'agreed with you', color: AppTheme.sprout),
          _Stat(_range(a), '95% range'),
          _Stat('${a.n}', 'answered'),
        ]),
        const SizedBox(height: AppTheme.s3),
        if (s.highConfidence.n > 0 && s.lowConfidence.n > 0)
          Text(
              'When the scanner was 80% sure or more: ${pct(s.highConfidence.value!)} right (${s.highConfidence.n}). '
              'Below 80%: ${pct(s.lowConfidence.value!)} right (${s.lowConfidence.n}). '
              '${s.highConfidence.value! > s.lowConfidence.value! ? 'Its confidence is a useful signal.' : 'Its confidence is not telling us much yet.'}',
              style: AppTheme.subhead),
        if (s.unsure > 0) Text('${s.unsure} marked Not sure and left out.', style: AppTheme.footnote),
      ]),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  final ImpactSummary s;
  const _ForecastCard(this.s);

  @override
  Widget build(BuildContext context) {
    if (s.forecastDays == 0) {
      return _Empty(s.forecastPending > 0
          ? '${s.forecastPending} forecast days are saved and waiting. Come back after they pass and the app will compare each one with what the weather did.'
          : 'The app saves each day\'s forecast and compares it with the real weather once the day has passed. Open the weather card to start.');
    }
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Stat(pct(s.rainCalls.value!), 'rain calls right', color: AppTheme.sprout),
          _Stat(_range(s.rainCalls), '95% range'),
          _Stat(s.tempMae == null ? '-' : '${s.tempMae!.toStringAsFixed(1)} C', 'average heat miss'),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text('Each forecast was made the day before and judged against observed rain and highest temperature. '
            'Rain counts at 1 mm or more. ${s.forecastPending} more days are waiting.',
            style: AppTheme.footnote),
      ]),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final ImpactSummary s;
  final ImpactData d;
  const _SavedCard(this.s, this.d);

  @override
  Widget build(BuildContext context) {
    if (s.savingEvents == 0) {
      return const _Empty('No confirmed savings yet. When rain does the work of a watering and you confirm you held off, '
          'the litres a daily schedule would have pumped are counted here. A delay is not a saving, so it is not counted.');
    }
    return GlassCard(
      child: Row(children: [
        _Stat('${s.litresSaved.round()} L', 'not pumped', color: AppTheme.sprout),
        _Stat('${s.savingEvents}', 'runs skipped'),
        _Stat('${(s.litresSaved / 1000).toStringAsFixed(1)} kL', 'about'),
      ]),
    );
  }
}

class _HarvestCard extends StatelessWidget {
  final ImpactSummary s;
  final ImpactData d;
  const _HarvestCard(this.s, this.d);

  @override
  Widget build(BuildContext context) {
    if (s.harvests == 0) {
      return const _Empty('Mark a crop as harvested on its plot page. The app compares the real day with the date it predicted.');
    }
    final bias = s.harvestBiasDays!;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Stat('${s.harvestMaeDays!.toStringAsFixed(1)} d', 'average miss', color: AppTheme.sprout),
          _Stat('${s.harvestWithin3} of ${s.harvests}', 'within 3 days'),
          _Stat(bias.abs() < 0.5 ? 'even' : bias > 0 ? 'late' : 'early', 'tends to be'),
        ]),
        if (s.harvests < minSampleToClaim)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s2),
            child: Text('${s.harvests} harvests is too few to claim a pattern.', style: AppTheme.footnote),
          ),
      ]),
    );
  }
}
