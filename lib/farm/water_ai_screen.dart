import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill, RingGauge, SectionTitle;
import '../crops/crop_store.dart';
import '../crops/my_crops_screen.dart' show showAddCrop;
import '../store/store_common.dart' show groupDigits;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../weather/weather_service.dart';
import 'farm_models.dart';
import 'farm_setup_screen.dart';
import 'farm_store.dart';
import 'irrigation_ai.dart';

const _water = Color(0xFF5AB8F0);

/// The irrigation AI: for every plot, whether to water today, how much and for
/// how long, and the week ahead. It plans from the crop, the soil, the real
/// weather and what the farmer tells it.
class WaterAiScreen extends ConsumerStatefulWidget {
  const WaterAiScreen({super.key});

  @override
  ConsumerState<WaterAiScreen> createState() => _WaterAiScreenState();
}

class _WaterAiScreenState extends ConsumerState<WaterAiScreen> {
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  Future<void> _tick() async {
    final started = await autopilotTick(ref.read);
    if (mounted && started.isNotEmpty) setState(() => _note = 'Autopilot opened the valve for ${started.join(', ')}.');
  }

  @override
  Widget build(BuildContext context) {
    final plots = ref.watch(cropStoreProvider);
    final farm = ref.watch(farmStoreProvider);
    final plan = ref.watch(irrigationProvider);
    final forecast = ref.watch(forecastProvider);
    final now = DateTime.now();

    return Scaffold(
      body: AppBackdrop(
        tint: _water,
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
                title: const Text('Irrigation AI'),
                actions: [
                  IconButton(
                    tooltip: 'My farm',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmSetupScreen())),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Water only when the plants need it', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text('The AI keeps a daily water balance for each plot and tells you when to water, how much and for how long.',
                      style: AppTheme.callout),
                  const SizedBox(height: AppTheme.s4),
                  if (plots.isEmpty)
                    GlassCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Add what you are growing and how big each plot is, then the AI can plan.', style: AppTheme.callout),
                        const SizedBox(height: AppTheme.s3),
                        GlassButton(label: 'Add a crop', icon: Icons.add_rounded, onPressed: () => showAddCrop(context)),
                      ]),
                    )
                  else ...[
                    if (!farm.isSetUp)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s3),
                        child: GlassCard(
                          tint: AppTheme.warn.withValues(alpha: 0.12),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmSetupScreen())),
                          child: Row(children: [
                            const Text('🧭', style: TextStyle(fontSize: 28)),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Set up your farm for exact run times', style: AppTheme.headline),
                                Text('Add the farm size, soil and how you water. Until then the AI assumes loam soil and sprinklers.',
                                    style: AppTheme.footnote),
                              ]),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                          ]),
                        ),
                      ),
                    if (plan == null)
                      GlassCard(
                        child: Row(children: [
                          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _water)),
                          const SizedBox(width: AppTheme.s3),
                          Expanded(child: Text(forecast.hasError ? 'Could not get the weather.' : 'Getting the weather...', style: AppTheme.callout)),
                        ]),
                      )
                    else ...[
                      if (_note != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s3),
                          child: GlassCard(tint: AppTheme.ok.withValues(alpha: 0.14), child: Text(_note!, style: AppTheme.callout)),
                        ),
                      _Summary(plan, farm),
                      const SizedBox(height: AppTheme.s3),
                      _Autopilot(plan, farm),
                      const SectionTitle('🌱', 'Your plots'),
                      for (final p in plan.plans)
                        Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: _PlotCard(p, now)),
                    ],
                  ],
                  const SizedBox(height: AppTheme.s4),
                  Text(
                      'How it works: the AI follows the FAO-56 water balance used by agronomists. Each day the crop uses the weather\'s evaporation times a crop factor, '
                      'rain that reaches the roots refills the soil, and watering is advised only when the crop would run short. It is a rule-based model, not a neural network. '
                      'It cannot see your soil, so a quick feel of the ground makes it far more accurate. It does not turn anything on by itself unless you link a smart valve.',
                      style: AppTheme.footnote),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final FarmIrrigation plan;
  final FarmProfile farm;
  const _Summary(this.plan, this.farm);

  @override
  Widget build(BuildContext context) {
    final today = plan.wateringToday;
    final rain = plan.weekRainWorkLitres;
    return GlassCard(
      tint: _water.withValues(alpha: 0.12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(today.isEmpty ? '✅' : '💧', style: const TextStyle(fontSize: 34)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(today.isEmpty ? 'No watering needed today' : '${today.length} ${today.length == 1 ? 'plot needs' : 'plots need'} water today',
                  style: AppTheme.title3),
              if (today.isNotEmpty) Text(today.map((p) => p.plot.name).join(', '), style: AppTheme.footnote),
            ]),
          ),
        ]),
        const SizedBox(height: AppTheme.s3),
        Text(
            'This week: ${groupDigits(plan.weekLitres.round())} litres planned.'
            '${rain > 1 ? ' Rain does ${groupDigits(rain.round())} litres of the work that a daily calendar would still have pumped (${(plan.savedPct * 100).round()}%).' : ' No useful rain is expected, so the plan only spaces the watering out to match what the soil can hold.'}',
            style: AppTheme.callout),
        for (final s in farm.sources.where((s) => s.isTank && s.capacityL > 0))
          Builder(builder: (context) {
            final draw = weekDrawFrom(s, farm, plan);
            final days = tankDays(s, draw);
            final low = days != null && days < 3;
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.s2),
              child: Text(
                  days == null
                      ? '${s.name} holds ${groupDigits(s.levelL.round())} litres. Nothing is drawn from it this week.'
                      : '${s.name}: ${groupDigits(s.levelL.round())} litres lasts about ${days.toStringAsFixed(1)} days of this plan.${low ? ' That is low. Top it up or ask for a delivery on Nolifa Drop.' : ''}',
                  style: AppTheme.footnote.copyWith(color: low ? AppTheme.danger : null)),
            );
          }),
      ]),
    );
  }
}

class _Autopilot extends ConsumerWidget {
  final FarmIrrigation plan;
  final FarmProfile farm;
  const _Autopilot(this.plan, this.farm);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valves = farm.systems.where((s) => s.valveUrl != null).length;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🤖', style: TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text('Autopilot', style: AppTheme.headline)),
          Switch(
            value: farm.autopilot,
            activeThumbColor: AppTheme.sprout,
            onChanged: valves == 0
                ? null
                : (v) {
                    HapticFeedback.mediumImpact();
                    ref.read(farmStoreProvider.notifier).setAutopilot(v);
                    if (v) autopilotTick(ref.read);
                  },
          ),
        ]),
        Text(
            valves == 0
                ? 'Link a smart valve to a system in My farm and the AI can open it for you each morning the plan calls for water. Until then it tells you what to do and you do it.'
                : farm.autopilot
                    ? 'On. When you open the app between 05:00 and 11:00 and a plot is due, the AI opens its valve for the planned minutes. It never runs a plot twice in a day.'
                    : 'Off. $valves ${valves == 1 ? 'system has' : 'systems have'} a valve linked.',
            style: AppTheme.footnote),
        if (valves > 0) Text('Today it works while the app is open. Running with the phone locked needs a small hub on the farm. That is on the road map.', style: AppTheme.caption),
      ]),
    );
  }
}

class _PlotCard extends ConsumerWidget {
  final PlotPlan plan;
  final DateTime now;
  const _PlotCard(this.plan, this.now);

  Color get _color => switch (plan.today.action) {
        DayAction.water => _water,
        DayAction.rainSkip => AppTheme.ok,
        DayAction.rest => AppTheme.textTertiary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = plan.plot;
    final t = plan.today;
    final store = ref.read(farmStoreProvider.notifier);
    final farm = ref.watch(farmStoreProvider);
    final ranToday = farm.runs.any((r) => r.plotId == p.id && dayKey(r.at) == dayKey(now));
    final held = farm.heldOff.contains('${p.id}|${dayKey(t.date)}');
    final sys = plan.system;

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RingGauge(
            value: plan.soilFullness,
            size: 58,
            color: plan.soilFullness < 0.25 ? AppTheme.danger : _water,
            center: Text(p.spec.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: AppTheme.headline),
              Text('${p.crop}  -  ${groupDigits(p.areaM2.round())} m2  -  soil ${(plan.soilFullness * 100).round()}% full', style: AppTheme.footnote),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                Pill(ranToday ? 'Watered today' : t.action.label, color: ranToday ? AppTheme.ok : _color),
                Pill('Sure: ${plan.confidenceLabel}', color: AppTheme.textSecondary),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: AppTheme.s3),
        if (t.action == DayAction.water && !ranToday) ...[
          Text(
              'Apply ${t.netMm.round()} mm: ${groupDigits(t.litres.round())} litres'
              '${t.minutes > 0 ? ' for about ${durationText(t.minutes)}' : ''}. Best before 08:00.',
              style: AppTheme.headline.copyWith(color: _water)),
          if (sys == null)
            Text('Pick how this plot is watered in My farm to get a run time.', style: AppTheme.caption)
          else
            Text('${sys.name}, ${(sys.efficiency * 100).round()}% efficient', style: AppTheme.caption),
          const SizedBox(height: AppTheme.s2),
          Row(children: [
            if (sys?.valveUrl != null)
              Expanded(
                child: GlassButton(
                  label: 'Open valve now',
                  icon: Icons.bolt_rounded,
                  accent: _water,
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final err = await store.runNow(plan);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Valve opened for ${durationText(t.minutes)}.')));
                    }
                  },
                ),
              ),
            if (sys?.valveUrl != null) const SizedBox(width: AppTheme.s2),
            Expanded(
              child: GhostButton(
                label: 'I watered',
                icon: Icons.check_rounded,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  store.logRun(p.id, t.litres);
                },
              ),
            ),
          ]),
        ] else if (!ranToday) ...[
          Text(
              t.action == DayAction.rainSkip
                  ? 'No watering today. Rain does the job: ${t.effRainMm.round()} mm of useful rain is expected.'
                  : 'No watering today. The soil still holds enough.',
              style: AppTheme.callout),
          if (t.rainWorkLitres >= 1) ...[
            const SizedBox(height: AppTheme.s2),
            GhostButton(
              label: held ? 'Counted as water saved' : 'I held off today',
              icon: held ? Icons.check_circle_rounded : Icons.savings_rounded,
              onPressed: held ? null : () => store.holdOff(p.id, p.name, t),
            ),
          ],
        ] else
          Text('You already watered this plot today.', style: AppTheme.callout),
        const SizedBox(height: AppTheme.s3),
        Text('How is the soil?', style: AppTheme.footnote),
        const SizedBox(height: 4),
        Wrap(spacing: AppTheme.s2, children: [
          for (final f in SoilFeel.values)
            ActionChip(
              label: Text(f.label),
              tooltip: f.hint,
              onPressed: () {
                HapticFeedback.selectionClick();
                store.soilCheck(p.id, f);
              },
            ),
        ]),
        const SizedBox(height: AppTheme.s3),
        _WeekStrip(plan, now),
        const SizedBox(height: AppTheme.s2),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('Why the AI says this', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
            children: [
              for (final w in plan.why)
                Padding(padding: const EdgeInsets.only(bottom: AppTheme.s2), child: Align(alignment: Alignment.centerLeft, child: Text(w, style: AppTheme.footnote))),
            ],
          ),
        ),
      ]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final PlotPlan plan;
  final DateTime now;
  const _WeekStrip(this.plan, this.now);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final d in plan.days)
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: d.action == DayAction.water ? _water.withValues(alpha: 0.2) : AppTheme.glassFill,
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              border: Border.all(color: d.action == DayAction.water ? _water : AppTheme.glassBorderSoft),
            ),
            child: Column(children: [
              Text(
                  DateTime(d.date.year, d.date.month, d.date.day) == DateTime(now.year, now.month, now.day)
                      ? 'Now'
                      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.date.weekday - 1],
                  style: AppTheme.caption),
              const SizedBox(height: 2),
              Text(switch (d.action) { DayAction.water => '💧', DayAction.rainSkip => '🌧️', DayAction.rest => '·' }, style: const TextStyle(fontSize: 16)),
              Text(d.litres > 0 ? (d.litres >= 1000 ? '${(d.litres / 1000).toStringAsFixed(1)}k' : '${d.litres.round()}') : '-', style: AppTheme.caption),
            ]),
          ),
        ),
    ]);
  }
}
