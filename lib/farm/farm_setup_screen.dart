import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill, SectionTitle;
import '../crops/crop_store.dart';
import '../store/store_common.dart' show SheetFrame, groupDigits, parseNumber;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'farm_models.dart';
import 'farm_store.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
/// Farm size, soil, where the water comes from, how it gets to the plants and
/// which plot uses which system. This is what the irrigation AI plans from.
class FarmSetupScreen extends ConsumerStatefulWidget {
  const FarmSetupScreen({super.key});

  @override
  ConsumerState<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends ConsumerState<FarmSetupScreen> {
  final _ha = TextEditingController();
  bool _haLoaded = false;

  @override
  void dispose() {
    _ha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farm = ref.watch(farmStoreProvider);
    final plots = ref.watch(cropStoreProvider);
    final store = ref.read(farmStoreProvider.notifier);
    if (!_haLoaded && farm.hectares > 0) {
      _ha.text = farm.hectares == farm.hectares.roundToDouble() ? farm.hectares.round().toString() : farm.hectares.toString();
      _haLoaded = true;
    }
    final plantedHa = plots.fold<double>(0, (a, p) => a + p.areaM2) / 10000;
    final share = farm.hectares > 0 ? plantedHa / farm.hectares : 0.0;

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
                title: const Text('My farm'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Set up your farm', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text('Tell the irrigation AI how big the farm is, what the ground is like and how the water reaches the plants.',
                      style: AppTheme.callout),
                  const SectionTitle('📐', 'Size and soil'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GlassField(
                        controller: _ha,
                        label: 'Farm size in hectares',
                        icon: Icons.square_foot_rounded,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          final n = parseNumber(v);
                          if (n != null && n > 0 && n <= 100000) store.setBasics(hectares: n);
                        },
                      ),
                      const SizedBox(height: AppTheme.s2),
                      Text('1 hectare is 10 000 square metres, about 1.4 football fields.', style: AppTheme.caption),
                      if (farm.hectares > 0) ...[
                        const SizedBox(height: AppTheme.s3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: share.clamp(0.0, 1.0),
                            minHeight: 8,
                            color: share > 1 ? AppTheme.danger : AppTheme.plantAccent,
                            backgroundColor: AppTheme.glassFillStrong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            share > 1
                                ? 'Your plots add up to ${plantedHa.toStringAsFixed(2)} ha, more than the farm. Check the sizes.'
                                : '${plantedHa.toStringAsFixed(2)} ha planted of ${farm.hectares.toString().replaceAll(RegExp(r'\.0$'), '')} ha (${(share * 100).round()}%)',
                            style: AppTheme.footnote),
                      ],
                      const SizedBox(height: AppTheme.s4),
                      Text('Soil', style: AppTheme.headline),
                      const SizedBox(height: AppTheme.s2),
                      Wrap(spacing: AppTheme.s2, children: [
                        for (final s in SoilType.values)
                          ChoiceChip(
                            label: Text(s.label),
                            selected: farm.soil == s,
                            onSelected: (_) => store.setBasics(soil: s),
                          ),
                      ]),
                      const SizedBox(height: AppTheme.s2),
                      Text(farm.soil.note, style: AppTheme.footnote),
                    ]),
                  ),
                  SectionTitle('🛢️', 'Water sources', trailing: TextButton(onPressed: () => _sourceSheet(context), child: const Text('Add'))),
                  if (farm.sources.isEmpty)
                    GlassCard(child: Text('Add a tank, borehole or tap so the AI can tell you how many days your water lasts.', style: AppTheme.callout))
                  else
                    for (final s in farm.sources)
                      Padding(padding: const EdgeInsets.only(bottom: AppTheme.s2), child: _SourceTile(s)),
                  SectionTitle('🚿', 'Irrigation systems', trailing: TextButton(onPressed: () => _systemSheet(context), child: const Text('Add'))),
                  if (farm.systems.isEmpty)
                    GlassCard(child: Text('Add how you water: drip lines, sprinklers, a pivot, flooding or a hose.', style: AppTheme.callout))
                  else
                    for (final s in farm.systems)
                      Padding(padding: const EdgeInsets.only(bottom: AppTheme.s2), child: _SystemTile(s)),
                  const SectionTitle('🌱', 'Which system waters which plot'),
                  if (plots.isEmpty)
                    GlassCard(child: Text('Add your crops first, then choose how each one is watered.', style: AppTheme.callout))
                  else
                    for (final p in plots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                          child: Row(children: [
                            Glyph(p.spec.emoji, size: 24),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: AppTheme.headline),
                                Text('${groupDigits(p.areaM2.round())} m2', style: AppTheme.caption),
                              ]),
                            ),
                            if (farm.systems.isEmpty)
                              Text('No system yet', style: AppTheme.caption)
                            else
                              DropdownButton<String?>(
                                value: farm.plotSystem[p.id],
                                hint: const Text('Choose'),
                                underline: const SizedBox.shrink(),
                                dropdownColor: AppTheme.sheet,
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Rain only')),
                                  for (final s in farm.systems) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                                ],
                                onChanged: (v) => store.assign(p.id, v),
                              ),
                          ]),
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

  Future<void> _sourceSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _SourceSheet(),
      );

  Future<void> _systemSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _SystemSheet(),
      );
}

class _SourceTile extends ConsumerWidget {
  final WaterSource s;
  const _SourceTile(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = s.isTank && s.capacityL > 0 ? (s.levelL / s.capacityL).clamp(0.0, 1.0) : null;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Glyph(s.kind.emoji, size: 26),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: AppTheme.headline),
              Text(
                  s.isTank
                      ? '${groupDigits(s.levelL.round())} of ${groupDigits(s.capacityL.round())} litres'
                      : s.capacityL > 0
                          ? 'Up to ${groupDigits(s.capacityL.round())} litres a day'
                          : s.kind.label,
                  style: AppTheme.footnote),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.textTertiary),
            tooltip: tr('Remove'),
            onPressed: () => ref.read(farmStoreProvider.notifier).removeSource(s.id),
          ),
        ]),
        if (pct != null) ...[
          const SizedBox(height: AppTheme.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              color: pct < 0.2 ? AppTheme.danger : const Color(0xFF5AB8F0),
              backgroundColor: AppTheme.glassFillStrong,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _setLevel(context, ref),
              child: const Text('Update the level'),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _setLevel(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: s.levelL.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('How much is in ${s.name}?', style: AppTheme.title3),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTheme.body,
          decoration: const InputDecoration(suffixText: 'litres'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, parseNumber(c.text)), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) ref.read(farmStoreProvider.notifier).setTankLevel(s.id, v);
  }
}

class _SystemTile extends ConsumerWidget {
  final IrrigationSystem s;
  const _SystemTile(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(farmStoreProvider);
    final src = farm.sourceOf(s);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Row(children: [
        Glyph(s.kind.emoji, size: 26),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: AppTheme.headline),
            Text('${s.kind.label}  -  ${groupDigits(s.flowLph.round())} L an hour  -  ${(s.efficiency * 100).round()}% of the water reaches the plants',
                style: AppTheme.footnote),
            if (src != null) Text('Draws from ${src.name}', style: AppTheme.caption),
            if (s.valveUrl != null) Pill('Smart valve linked', color: AppTheme.ok, icon: Icons.bolt_rounded),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.textTertiary),
          tooltip: tr('Remove'),
          onPressed: () => ref.read(farmStoreProvider.notifier).removeSystem(s.id),
        ),
      ]),
    );
  }
}

class _SourceSheet extends ConsumerStatefulWidget {
  const _SourceSheet();

  @override
  ConsumerState<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends ConsumerState<_SourceSheet> {
  WaterSourceKind _kind = WaterSourceKind.tank;
  final _name = TextEditingController();
  final _cap = TextEditingController();
  final _level = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _cap.dispose();
    _level.dispose();
    super.dispose();
  }

  void _save() {
    final cap = parseNumber(_cap.text) ?? 0;
    final level = parseNumber(_level.text) ?? 0;
    if (_kind == WaterSourceKind.tank && cap <= 0) {
      setState(() => _error = 'Enter the tank size in litres');
      return;
    }
    if (cap < 0 || cap > 100000000) {
      setState(() => _error = 'That size does not look right');
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(farmStoreProvider.notifier).addSource(_kind, _name.text, capacityL: cap, levelL: _kind == WaterSourceKind.tank ? level : 0);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
        title: 'Add a water source',
        subtitle: 'Where the irrigation water comes from.',
        children: [
          Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
            for (final k in WaterSourceKind.values)
              ChoiceChip(label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: AppTheme.s3),
          GlassField(controller: _name, label: 'Name (optional)', icon: Icons.label_rounded),
          const SizedBox(height: AppTheme.s3),
          GlassField(
            controller: _cap,
            label: _kind == WaterSourceKind.tank ? 'Tank size in litres' : 'Most you can take in a day, litres (optional)',
            icon: Icons.water_rounded,
            keyboardType: TextInputType.number,
          ),
          if (_kind == WaterSourceKind.tank) ...[
            const SizedBox(height: AppTheme.s3),
            GlassField(controller: _level, label: 'How much is in it now, litres', icon: Icons.opacity_rounded, keyboardType: TextInputType.number),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s1), child: Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger))),
          const SizedBox(height: AppTheme.s4),
          GlassButton(label: 'Add source', icon: Icons.check_rounded, onPressed: _save),
        ],
      );
}

class _SystemSheet extends ConsumerStatefulWidget {
  const _SystemSheet();

  @override
  ConsumerState<_SystemSheet> createState() => _SystemSheetState();
}

class _SystemSheetState extends ConsumerState<_SystemSheet> {
  IrrigationKind _kind = IrrigationKind.drip;
  final _name = TextEditingController();
  final _flow = TextEditingController(text: '1500');
  final _valve = TextEditingController();
  String? _source;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _flow.dispose();
    _valve.dispose();
    super.dispose();
  }

  void _save() {
    final flow = parseNumber(_flow.text);
    if (flow == null || flow <= 0 || flow > 10000000) {
      setState(() => _error = 'Enter how many litres an hour flow when one plot is on');
      return;
    }
    final valve = _valve.text.trim();
    if (valve.isNotEmpty && !(valve.startsWith('http://') || valve.startsWith('https://'))) {
      setState(() => _error = 'The valve link must start with http:// or https://');
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(farmStoreProvider.notifier).addSystem(_kind, _name.text, flow, sourceId: _source, valveUrl: valve);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(farmStoreProvider).sources;
    return SheetFrame(
      title: 'Add an irrigation system',
      subtitle: 'How the water gets to the plants.',
      children: [
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          for (final k in IrrigationKind.values)
            ChoiceChip(label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text('${(_kind.efficiency * 100).round()}% of the water from this kind of system reaches the plants. The rest is lost to wind, run-off and evaporation.',
            style: AppTheme.caption),
        const SizedBox(height: AppTheme.s3),
        GlassField(controller: _name, label: 'Name (optional)', icon: Icons.label_rounded),
        const SizedBox(height: AppTheme.s3),
        GlassField(
          controller: _flow,
          label: 'Litres an hour when one plot is on',
          icon: Icons.speed_rounded,
          keyboardType: TextInputType.number,
        ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: AppTheme.s3),
          Text('Draws from', style: AppTheme.footnote),
          Wrap(spacing: AppTheme.s2, children: [
            ChoiceChip(label: const Text('Not sure'), selected: _source == null, onSelected: (_) => setState(() => _source = null)),
            for (final s in sources) ChoiceChip(label: Text(s.name), selected: _source == s.id, onSelected: (_) => setState(() => _source = s.id)),
          ]),
        ],
        const SizedBox(height: AppTheme.s3),
        GlassField(
          controller: _valve,
          label: 'Smart valve link (optional)',
          icon: Icons.bolt_rounded,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: AppTheme.s1),
        Text(
            'Only if you have a smart valve or relay on your Wi-Fi. A link with {minutes} in it gets a timer, for example http://192.168.1.50/relay/0?turn=on&timer={seconds}. Leave it empty to water by hand and let the app tell you when.',
            style: AppTheme.caption),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s1), child: Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger))),
        const SizedBox(height: AppTheme.s4),
        GlassButton(label: 'Add system', icon: Icons.check_rounded, onPressed: _save),
      ],
    );
  }
}
