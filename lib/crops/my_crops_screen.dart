import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill, Reveal, RingGauge, SectionTitle;
import '../services/crop_scan.dart';
import '../store/store_common.dart' show SheetFrame, parseNumber;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../farm/farm_setup_screen.dart';
import '../farm/water_ai_screen.dart';
import '../impact/impact_models.dart';
import '../impact/impact_store.dart';
import 'crop_models.dart';
import '../weather/weather_service.dart';
import '../weather/weather_threats.dart';
import 'crop_store.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr, trn;
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

Color healthColor(int? score) => score == null
    ? AppTheme.textTertiary
    : score >= 75
        ? AppTheme.ok
        : score >= 45
            ? AppTheme.warn
            : AppTheme.danger;

String harvestLine(CropOutlook o) {
  if (o.overdue) return 'Past the best harvest window';
  if (o.ready) return 'Ready to harvest now';
  if (o.daysToHarvest == o.daysToHarvestHigh) return 'Harvest in ${o.daysToHarvest} days';
  return 'Harvest in ${o.daysToHarvest} to ${o.daysToHarvestHigh} days';
}

/// Every plot the farmer is growing, with how far along each one is.
class MyCropsScreen extends ConsumerWidget {
  const MyCropsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plots = ref.watch(cropStoreProvider);
    final now = DateTime.now();
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
                title: const Text('My crops'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Crop health AI', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text(
                      'Add what you planted. The AI tracks each plot, tells you how far along it is and when to harvest, and helps you set up sprinklers.',
                      style: AppTheme.callout),
                  const SizedBox(height: AppTheme.s4),
                  GlassButton(
                    label: 'Add a crop',
                    icon: Icons.add_rounded,
                    onPressed: () => showAddCrop(context),
                  ),
                  const SizedBox(height: AppTheme.s2),
                  Row(children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Irrigation AI',
                        icon: Icons.water_drop_rounded,
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterAiScreen())),
                      ),
                    ),
                    const SizedBox(width: AppTheme.s2),
                    Expanded(
                      child: GhostButton(
                        label: 'My farm',
                        icon: Icons.agriculture_rounded,
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmSetupScreen())),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppTheme.s4),
                  if (plots.isEmpty)
                    GlassCard(
                      child: Row(children: [
                        const Text('🌱', style: TextStyle(fontSize: 34)),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text('No crops yet. Add your first plot and get a harvest date.',
                              style: AppTheme.callout),
                        ),
                      ]),
                    )
                  else
                    for (var i = 0; i < plots.length; i++)
                      Reveal(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s3),
                          child: _PlotCard(plots[i], CropAdvisor.assess(plots[i], now)),
                        ),
                      ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlotCard extends StatelessWidget {
  final CropPlot plot;
  final CropOutlook o;
  const _PlotCard(this.plot, this.o);

  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => CropDetailScreen(plotId: plot.id))),
        child: Row(children: [
          RingGauge(
            value: o.progress,
            size: 64,
            color: o.ready ? AppTheme.warn : AppTheme.plantAccent,
            center: Text(plot.spec.emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plot.name, style: AppTheme.headline),
              Text('${plot.crop}  •  ${o.stage}', style: AppTheme.footnote),
              const SizedBox(height: AppTheme.s1),
              Text(harvestLine(o),
                  style: AppTheme.subhead.copyWith(
                      color: o.ready ? AppTheme.warn : AppTheme.plantAccent,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: AppTheme.s2),
              Wrap(spacing: AppTheme.s2, children: [
                Pill(o.healthScore == null ? 'Not scanned' : 'Health ${o.healthScore}',
                    color: healthColor(o.healthScore)),
                if (plot.sprinkler.enabled)
                  const Pill('Sprinkler on', color: Color(0xFF5AB8F0), icon: Icons.water_drop_rounded),
              ]),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
      );
}

// ------------------------------------------------------------------ detail

class CropDetailScreen extends ConsumerWidget {
  final String plotId;
  const CropDetailScreen({super.key, required this.plotId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plot = ref.watch(cropStoreProvider).where((p) => p.id == plotId).firstOrNull;
    if (plot == null) {
      return Scaffold(
        body: AppBackdrop(child: SafeArea(child: Center(child: Text('This plot was removed.', style: AppTheme.callout)))),
      );
    }
    final now = DateTime.now();
    final o = CropAdvisor.assess(plot, now);
    final store = ref.read(cropStoreProvider.notifier);
    final spec = plot.spec;
    final fc = ref.watch(forecastProvider).valueOrNull;
    final rainNote = fc == null ? null : sprinklerAdvice(fc, plot, now);

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
                title: Text(plot.name),
                actions: [
                  IconButton(
                    tooltip: tr('Remove plot'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppTheme.sheet,
                          title: Text('Remove ${plot.name}?', style: AppTheme.title3),
                          content: Text('Its scans and sprinkler plan are deleted too.', style: AppTheme.callout),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        store.remove(plot.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Reveal(
                    child: GlassCard(
                      tint: AppTheme.plantAccent.withValues(alpha: 0.10),
                      child: Column(children: [
                        Row(children: [
                          RingGauge(
                            value: o.progress,
                            size: 92,
                            color: o.ready ? AppTheme.warn : AppTheme.plantAccent,
                            center: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(spec.emoji, style: const TextStyle(fontSize: 26)),
                              Text('${(o.progress * 100).round()}%', style: AppTheme.footnote),
                            ]),
                          ),
                          const SizedBox(width: AppTheme.s4),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.stage, style: AppTheme.title2),
                              const SizedBox(height: AppTheme.s1),
                              Text(harvestLine(o),
                                  style: AppTheme.headline.copyWith(
                                      color: o.ready ? AppTheme.warn : AppTheme.plantAccent)),
                              if (!o.ready)
                                Text('Around ${shortDate(o.harvestOn)}', style: AppTheme.footnote),
                              Text('Day ${o.daysGrowing} of about ${spec.daysToHarvest}', style: AppTheme.caption),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: AppTheme.s4),
                        Row(children: [
                          for (var i = 0; i < spec.stages.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Column(children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: o.ready || i <= o.stageIndex
                                          ? (o.ready ? AppTheme.warn : AppTheme.plantAccent)
                                          : AppTheme.glassFillStrong,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(spec.stages[i].$1,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: AppTheme.caption.copyWith(
                                          color: !o.ready && i == o.stageIndex
                                              ? AppTheme.textPrimary
                                              : AppTheme.textTertiary)),
                                ]),
                              ),
                            ),
                        ]),
                        const SizedBox(height: AppTheme.s3),
                        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                          Pill('Confidence ${o.confidence}', color: AppTheme.textSecondary),
                          Pill(
                              o.rate >= 0.99
                                  ? 'On calendar'
                                  : 'Running ${((1 - o.rate) * 100).round()}% slow',
                              color: o.rate >= 0.99 ? AppTheme.ok : AppTheme.warn),
                        ]),
                        const SizedBox(height: AppTheme.s2),
                        Text(
                            'An estimate from the crop calendar, your scans and your watering. It sharpens every time you scan.',
                            style: AppTheme.caption),
                      ]),
                    ),
                  ),
                  const SectionTitle('🩺', 'Plant health'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        RingGauge(
                          value: (o.healthScore ?? 0) / 100,
                          size: 62,
                          color: healthColor(o.healthScore),
                          center: Text(o.healthScore?.toString() ?? '-', style: AppTheme.headline),
                        ),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                                plot.checks.isEmpty
                                    ? 'Not scanned yet'
                                    : plot.checks.first.label,
                                style: AppTheme.headline),
                            Text(
                                plot.checks.isEmpty
                                    ? 'Scan a leaf to start'
                                    : 'Scanned ${shortDate(plot.checks.first.at)}',
                                style: AppTheme.footnote),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: AppTheme.s3),
                      GlassButton(
                        label: 'Scan this plot now',
                        icon: Icons.camera_alt_rounded,
                        onPressed: () => startCropScan(context, ref,
                            onDiagnosed: (label, severity) => store.addCheck(plot.id, label, severity)),
                      ),
                      if (plot.checks.length > 1) ...[
                        const SizedBox(height: AppTheme.s3),
                        for (final c in plot.checks.skip(1).take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s1),
                            child: Row(children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: switch (c.severity) {
                                        'red' => AppTheme.danger,
                                        'orange' => AppTheme.warn,
                                        _ => AppTheme.ok,
                                      },
                                      shape: BoxShape.circle)),
                              const SizedBox(width: AppTheme.s2),
                              Expanded(child: Text(c.label, style: AppTheme.footnote)),
                              Text(shortDate(c.at), style: AppTheme.caption),
                            ]),
                          ),
                      ],
                    ]),
                  ),
                  const SectionTitle('💧', 'Sprinkler'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (!plot.sprinkler.enabled)
                        Text(
                            'No sprinkler plan. The crop needs about ${o.waterNeedLitresPerDay.round()} litres a day at this stage.',
                            style: AppTheme.callout)
                      else ...[
                        Text(
                            '${plot.sprinkler.minutesPerRun} min at ${plot.sprinkler.startHours.map((h) => '${h.toString().padLeft(2, '0')}:00').join(' and ')}',
                            style: AppTheme.headline),
                        Text(
                            '${plot.sprinkler.litresPerDay.round()} L a day against ${o.waterNeedLitresPerDay.round()} L needed'
                            '${o.waterRatio == null ? '' : ' (${(o.waterRatio! * 100).round()}%)'}',
                            style: AppTheme.footnote),
                        if (plot.sprinkler.nextRun(now) != null)
                          Text(
                              'Next run ${plot.sprinkler.nextRun(now)!.day == now.day ? 'today' : 'tomorrow'} at ${plot.sprinkler.nextRun(now)!.hour.toString().padLeft(2, '0')}:00',
                              style: AppTheme.caption),
                      ],
                      const SizedBox(height: AppTheme.s3),
                      GlassButton(
                        label: plot.sprinkler.enabled ? 'Change sprinkler plan' : 'Set up sprinkler',
                        icon: Icons.water_drop_rounded,
                        accent: const Color(0xFF5AB8F0),
                        onPressed: () => showSprinklerSheet(context, plot),
                      ),
                    ]),
                  ),
                  const SectionTitle('🧺', 'Harvest'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          'Harvested? Tell the app the day. It compares it with the date it predicted when you added the crop, and that is how its accuracy is measured on the Impact page.',
                          style: AppTheme.callout),
                      const SizedBox(height: AppTheme.s3),
                      GlassButton(
                        label: 'Mark as harvested today',
                        icon: Icons.check_circle_rounded,
                        accent: AppTheme.warn,
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.sheet,
                              title: Text('Harvested ${plot.name}?', style: AppTheme.title3),
                              content: Text('When you added it the app expected ${shortDate(plot.predictedOn ?? o.harvestOn)}. The plot is removed from your list.',
                                  style: AppTheme.callout),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, harvested')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          final today = DateTime(now.year, now.month, now.day);
                          // Judge it against what the app said when the crop was added.
                          final said = plot.predictedOn ?? o.harvestOn;
                          ref.read(impactStoreProvider.notifier).logHarvest(HarvestLog(
                              now, plot.name, plot.crop, DateTime(said.year, said.month, said.day), today));
                          store.remove(plot.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ]),
                  ),
                  const SectionTitle('💡', 'What to do'),
                  if (rainNote != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s2),
                      child: GlassCard(
                        tint: const Color(0xFF5AB8F0).withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                        child: Text('🌧️ $rainNote', style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
                      ),
                    ),
                  for (final a in o.advice)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s2),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                        child: Text(a, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sheets

Future<void> showAddCrop(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCropSheet(),
    );

class _AddCropSheet extends ConsumerStatefulWidget {
  const _AddCropSheet();

  @override
  ConsumerState<_AddCropSheet> createState() => _AddCropSheetState();
}

class _AddCropSheetState extends ConsumerState<_AddCropSheet> {
  String _crop = cropSpecs.first.name;
  final _name = TextEditingController();
  final _area = TextEditingController(text: '100');
  DateTime _planted = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  void _save() {
    final area = parseNumber(_area.text);
    if (area == null || area <= 0 || area > 1000000) {
      setState(() => _error = 'Enter the plot size in square metres');
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(cropStoreProvider.notifier).add(crop: _crop, name: _name.text, plantedOn: _planted, areaM2: area);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = <(String, int)>[('Today', 0), ('1 week ago', 7), ('2 weeks ago', 14), ('1 month ago', 30)];
    return SheetFrame(
      title: 'Add a crop',
      subtitle: 'What you planted and when. The AI works out the rest.',
      children: [
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          for (final c in cropSpecs)
            ChoiceChip(
              label: Text('${c.emoji} ${c.name}'),
              selected: _crop == c.name,
              onSelected: (_) => setState(() => _crop = c.name),
            ),
        ]),
        const SizedBox(height: AppTheme.s3),
        GlassField(controller: _name, label: 'Plot name (optional)', icon: Icons.label_rounded),
        const SizedBox(height: AppTheme.s3),
        GlassField(
          controller: _area,
          label: 'Plot size in square metres',
          icon: Icons.crop_square_rounded,
          keyboardType: TextInputType.number,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s1),
            child: Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger)),
          ),
        const SizedBox(height: AppTheme.s3),
        Text('Planted', style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s1),
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o.$1),
              selected: _planted.difference(now).inDays.abs() == o.$2 && _planted.day == now.subtract(Duration(days: o.$2)).day,
              onSelected: (_) => setState(() => _planted = now.subtract(Duration(days: o.$2))),
            ),
          ActionChip(
            avatar: const Icon(Icons.calendar_month_rounded, size: 16),
            label: Text(shortDate(_planted)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _planted,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now,
              );
              if (d != null) setState(() => _planted = d);
            },
          ),
        ]),
        const SizedBox(height: AppTheme.s4),
        GlassButton(label: 'Start tracking', icon: Icons.eco_rounded, onPressed: _save),
      ],
    );
  }
}

Future<void> showSprinklerSheet(BuildContext context, CropPlot plot) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SprinklerSheet(plot),
    );

class _SprinklerSheet extends ConsumerStatefulWidget {
  final CropPlot plot;
  const _SprinklerSheet(this.plot);

  @override
  ConsumerState<_SprinklerSheet> createState() => _SprinklerSheetState();
}

class _SprinklerSheetState extends ConsumerState<_SprinklerSheet> {
  late SprinklerPlan _plan = widget.plot.sprinkler.enabled
      ? widget.plot.sprinkler
      : widget.plot.sprinkler.copyWith(enabled: true);

  static const _hours = [5, 6, 7, 17, 18, 19];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final test = widget.plot.copyWith(sprinkler: _plan);
    final o = CropAdvisor.assess(test, now);
    final ratio = o.waterRatio ?? 0;
    final tone = ratio < 0.6 ? AppTheme.danger : (ratio < 0.9 || ratio > 1.5 ? AppTheme.warn : AppTheme.ok);

    Widget stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Row(children: [
          Expanded(child: Text(label, style: AppTheme.body)),
          IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline_rounded)),
          SizedBox(width: 64, child: Text(value, textAlign: TextAlign.center, style: AppTheme.headline)),
          IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]);

    return SheetFrame(
      title: 'Sprinkler plan',
      subtitle: '${widget.plot.name}: ${widget.plot.areaM2.round()} m² of ${widget.plot.crop.toLowerCase()}',
      children: [
        GlassCard(
          tint: tone.withValues(alpha: 0.12),
          padding: const EdgeInsets.all(AppTheme.s3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_plan.litresPerDay.round()} L a day of ${o.waterNeedLitresPerDay.round()} L needed',
                style: AppTheme.headline),
            Text(
                ratio < 0.6
                    ? 'Far too dry. The crop will grow slowly.'
                    : ratio < 0.9
                        ? 'A little short.'
                        : ratio > 1.5
                            ? 'More than it needs. Risk of root rot.'
                            : 'About right for this stage.',
                style: AppTheme.footnote),
          ]),
        ),
        const SizedBox(height: AppTheme.s3),
        stepper('Sprinkler flow (L per minute)', _plan.litresPerMinute.round().toString(),
            () => setState(() => _plan = _plan.copyWith(litresPerMinute: (_plan.litresPerMinute - 1).clamp(1, 200))),
            () => setState(() => _plan = _plan.copyWith(litresPerMinute: (_plan.litresPerMinute + 1).clamp(1, 200)))),
        stepper('Minutes per run', '${_plan.minutesPerRun}',
            () => setState(() => _plan = _plan.copyWith(minutesPerRun: (_plan.minutesPerRun - 5).clamp(5, 240))),
            () => setState(() => _plan = _plan.copyWith(minutesPerRun: (_plan.minutesPerRun + 5).clamp(5, 240)))),
        Text('Start times', style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s1),
        Wrap(spacing: AppTheme.s2, children: [
          for (final h in _hours)
            FilterChip(
              label: Text('${h.toString().padLeft(2, '0')}:00'),
              selected: _plan.startHours.contains(h),
              onSelected: (on) => setState(() {
                final hrs = {..._plan.startHours};
                on ? hrs.add(h) : hrs.remove(h);
                if (hrs.isNotEmpty) _plan = _plan.copyWith(startHours: hrs.toList()..sort());
              }),
            ),
        ]),
        const SizedBox(height: AppTheme.s3),
        GhostButton(
          label: 'Let the AI suggest a plan',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => setState(() => _plan = CropAdvisor.suggest(widget.plot, now, litresPerMinute: _plan.litresPerMinute)),
        ),
        const SizedBox(height: AppTheme.s3),
        GlassButton(
          label: 'Save plan',
          icon: Icons.check_rounded,
          onPressed: () {
            ref.read(cropStoreProvider.notifier).setSprinkler(widget.plot.id, _plan);
            Navigator.pop(context);
          },
        ),
        if (widget.plot.sprinkler.enabled)
          TextButton(
            onPressed: () {
              ref.read(cropStoreProvider.notifier).setSprinkler(widget.plot.id, widget.plot.sprinkler.copyWith(enabled: false));
              Navigator.pop(context);
            },
            child: const Text('Turn the plan off'),
          ),
        Text('Nolifa does not switch your sprinkler. Run it on this schedule and the AI uses it to estimate your harvest.',
            style: AppTheme.caption),
      ],
    );
  }
}
