import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../live/location.dart';
import '../market/market_store.dart';
import '../market/account_screens.dart' show PhoneVerifyScreen;
import '../market/market_widgets.dart';
import '../market/shop_screens.dart';
import '../market/trust_screens.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'provider_desk.dart';
import 'water_forecast.dart';
import 'dws_feed.dart';
import 'water_models.dart';
import 'water_store.dart';
import 'water_widgets.dart';

/// The community water page as a tab, with an optional close button.
///
/// [extraSections] lets the host app slot its own cards in (Nolifa adds the
/// farm's water use), each revealed on scroll like the rest.
class WaterPage extends StatelessWidget {
  final VoidCallback? onClose;
  final List<Widget> extraSections;
  const WaterPage({super.key, this.onClose, this.extraSections = const <Widget>[]});

  @override
  Widget build(BuildContext context) =>
      _WaterView(onClose: onClose, extraSections: extraSections, bottomPad: 140);
}

/// The same page as a full screen, opened from an alert or another app.
class WaterScreen extends StatelessWidget {
  final List<Widget> extraSections;
  const WaterScreen({super.key, this.extraSections = const <Widget>[]});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Column(children: [
              const WaterBackRow(),
              Expanded(child: _WaterView(extraSections: extraSections, bottomPad: AppTheme.s10)),
            ]),
          ),
        ),
      );
}

/// The page body, shared by the tab and the full screen. Holds what must
/// survive scrolling a section out of sight: the ticked checklist.
class _WaterView extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final List<Widget> extraSections;
  final double bottomPad;
  const _WaterView({this.onClose, required this.extraSections, required this.bottomPad});

  @override
  ConsumerState<_WaterView> createState() => _WaterViewState();
}

class _WaterViewState extends ConsumerState<_WaterView> {
  final _ticked = <int>{};

  void _tick(int i) => setState(() => _ticked.contains(i) ? _ticked.remove(i) : _ticked.add(i));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(waterProvider);
    final zone = s.myZone;
    final forecast = (zone == null ? null : s.forecastOf(zone.id)) ?? forecastWater(const []);
    final sections = <(String, Widget)>[
      ('community', _CommunitySection(state: s)),
      if (zone != null) ...[
        ('supply', Padding(padding: const EdgeInsets.only(top: AppTheme.s4), child: _SupplyCard(zone: zone))),
        ('radar', _RadarSection(forecast: forecast, level: zone.level)),
        ('voice', _VoiceSection(state: s, zone: zone)),
        ('source', Padding(padding: const EdgeInsets.only(top: AppTheme.s4), child: _SourceCard(state: s, zone: zone))),
      ],
      ('prepare', _PrepareSection(forecast: forecast, ticked: _ticked, onTick: _tick)),
      for (var i = 0; i < widget.extraSections.length; i++)
        ('extra-$i', Padding(padding: const EdgeInsets.only(top: AppTheme.s6), child: widget.extraSections[i])),
      ('real', const RealDamLevels()),
      if (ref.read(waterProvider.notifier).isProvider) ('provider', const _ProviderEntry()),
      if (s.demo) ('demo', _DemoControls(state: s)),
    ];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '💧',
            title: 'Water',
            subtitle: "Your community's supply, forecast and help",
            accent: AppTheme.sprout,
            trailing: HeaderActions(onClose: widget.onClose),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, widget.bottomPad),
          sliver: SliverList.builder(
            itemCount: sections.length,
            findChildIndexCallback: (key) {
              final i = sections.indexWhere((e) => ValueKey(e.$1) == key);
              return i < 0 ? null : i;
            },
            itemBuilder: (_, i) => Reveal(key: ValueKey(sections[i].$1), index: i, child: sections[i].$2),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ community

class _CommunitySection extends ConsumerWidget {
  final WaterState state;
  const _CommunitySection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = state.myZone;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('📍', 'Your community'),
      if (zone == null)
        state.demo ? const _LoadingCard() : const _NoReadingsCard()
      else ...[
        _ZonePicker(
          zones: state.zones,
          selectedId: zone.id,
          onSelect: (id) {
            HapticFeedback.selectionClick();
            ref.read(waterProvider.notifier).selectZone(id);
          },
        ),
        const SizedBox(height: AppTheme.s3),
        Wrap(spacing: AppTheme.s3, runSpacing: AppTheme.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(zone.provider, style: AppTheme.footnote),
          Text('Updated ${agoText(zone.updated)}', style: AppTheme.footnote),
          if (zone.demo) Pill('Provider feed (demo)', color: AppTheme.warn, icon: Icons.science_rounded),
        ]),
      ],
    ]);
  }
}

/// The community chips. Keeps the chosen one in view, so the home community
/// is never hiding off the edge of the row.
class _ZonePicker extends StatefulWidget {
  final List<WaterZone> zones;
  final String selectedId;
  final void Function(String id) onSelect;
  const _ZonePicker({required this.zones, required this.selectedId, required this.onSelect});

  @override
  State<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<_ZonePicker> {
  final _scroll = ScrollController();
  final _selected = GlobalKey();
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _bringIntoView();
  }

  @override
  void didUpdateWidget(covariant _ZonePicker old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) _bringIntoView();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Centres the chosen chip in the row only. The page itself never moves.
  void _bringIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _selected.currentContext?.findRenderObject();
      if (!mounted || box == null || !_scroll.hasClients) return;
      final p = _scroll.position;
      final target = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.5).offset
          .clamp(p.minScrollExtent, p.maxScrollExtent);
      if (_first) {
        _scroll.jumpTo(target);
        _first = false;
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: [
          for (final z in widget.zones)
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.s2),
              child: WaterChip(
                key: z.id == widget.selectedId ? _selected : null,
                label: z.name,
                selected: z.id == widget.selectedId,
                dot: z.status.color,
                onTap: () => widget.onSelect(z.id),
              ),
            ),
        ]),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.sprout)),
          const SizedBox(width: AppTheme.s3),
          Text('Loading communities', style: AppTheme.callout),
        ]),
      );
}

class _NoReadingsCard extends StatelessWidget {
  const _NoReadingsCard();

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💧', style: const TextStyle(fontSize: 34)),
          const SizedBox(height: AppTheme.s2),
          Text('No readings for your area yet', style: AppTheme.title3),
          const SizedBox(height: AppTheme.s2),
          Text(
              'Your water provider has not shared data for this area yet. When they do, '
              'you will see the supply level, a forecast and a way to ask for help here. '
              'You can still get ready below.',
              style: AppTheme.callout),
        ]),
      );
}

// --------------------------------------------------------------- supply

String _blurb(WaterStatus s) => switch (s) {
      WaterStatus.healthy => 'Plenty in the reservoir. Nothing to do.',
      WaterStatus.watch => 'Falling. Worth keeping an eye on.',
      WaterStatus.low => 'Low. You can now ask the provider for help.',
      WaterStatus.critical => 'Critical. Stock up now and ask for trucks.',
    };

class _SupplyCard extends StatelessWidget {
  final WaterZone zone;
  const _SupplyCard({required this.zone});

  @override
  Widget build(BuildContext context) {
    final status = zone.status;
    return GlassCard(
      tint: status.color.withValues(alpha: 0.10),
      child: Row(children: [
        RingGauge(
          value: zone.level / 100,
          size: 128,
          color: status.color,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              CountUp(zone.level, prefix: '', style: AppTheme.title1),
              Text('%', style: AppTheme.callout),
            ]),
            Text('full', style: AppTheme.caption),
          ]),
        ),
        const SizedBox(width: AppTheme.s5),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pill(status.label, color: status.color, icon: Icons.water_drop_rounded),
            const SizedBox(height: AppTheme.s2),
            Text(zone.reservoir.isEmpty ? zone.name : zone.reservoir, style: AppTheme.headline),
            Text('${groupDigits(zone.population)} people served', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s2),
            Text(_blurb(status), style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- radar

class _RadarSection extends StatelessWidget {
  final WaterForecast forecast;
  final double level;
  const _RadarSection({required this.forecast, required this.level});

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final ready = f.confidence > 0;
    final empty = f.daysToEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('📡', 'Water radar'),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Forecast from the reservoir's readings", style: AppTheme.caption),
          const SizedBox(height: AppTheme.s2),
          Text(forecastHeadline(f), style: AppTheme.title2.copyWith(color: forecastColor(f))),
          const SizedBox(height: 2),
          Text(f.why, style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s4),
          if (ready) ...[
            WaterRadarChart(now: level, days: f.days),
            const SizedBox(height: AppTheme.s4),
            Row(children: [
              Expanded(
                child: StatTile(
                  label: 'Days to empty',
                  value: empty == null ? 'No empty date' : (empty <= 0 ? 'Empty' : daysText(empty)),
                ),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: StatTile(
                  label: 'Trend',
                  value: '${f.changePerDay > 0 ? '+' : ''}${f.changePerDay.toStringAsFixed(1)}% a day',
                ),
              ),
            ]),
          ] else
            Text('The radar needs at least 4 readings from the provider before it can forecast.',
                style: AppTheme.callout),
          const SizedBox(height: AppTheme.s4),
          ConfidenceMeter(value: f.confidence),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- voice

class _VoiceSection extends ConsumerWidget {
  final WaterState state;
  final WaterZone zone;
  const _VoiceSection({required this.state, required this.zone});

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final result = await ref.read(waterProvider.notifier).vote();
    if (result == VoteResult.counted || !context.mounted) return;
    // Not eligible while the supply is already low means the request moved on
    // to the provider before this tap landed.
    final low = ref.read(waterProvider).myZone?.status.canRequestHelp ?? false;
    if (result == VoteResult.notVerified) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: const Text('Only verified people can vote, so every vote is a real person.'),
        action: SnackBarAction(
          label: 'Verify',
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen())),
        ),
      ));
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(switch (result) {
        VoteResult.alreadyVoted => 'You already asked for help. Each person counts once.',
        VoteResult.notVerified => 'Verify your phone to vote.',
        _ when low => 'This request is already with the provider.',
        _ => 'Help requests open when supply drops below 40%.',
      }),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incident = state.incidentOf(zone.id);
    final newest = newestIncident(state.incidents, zone.id);
    final resolved = incident == null && newest?.stage == IncidentStage.resolved ? newest : null;
    final open = zone.status.canRequestHelp || incident != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('🤝', 'Community voice'),
      if (open)
        _HelpCard(
          zone: zone,
          incident: incident,
          resolved: resolved,
          voted: state.votedIn(incident),
          onAsk: () => _ask(context, ref),
        )
      else
        _CalmCard(zone: zone, resolved: resolved),
    ]);
  }
}

class _CalmCard extends StatelessWidget {
  final WaterZone zone;
  final WaterIncident? resolved;
  const _CalmCard({required this.zone, required this.resolved});

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💚', style: TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No help needed right now', style: AppTheme.headline),
              const SizedBox(height: 2),
              Text('Help requests open when supply drops below 40%. ${zone.name} is at ${zone.level.round()}%.',
                  style: AppTheme.footnote),
              if (resolved != null) ...[
                const SizedBox(height: AppTheme.s2),
                _ResolvedLine(incident: resolved!),
              ],
            ]),
          ),
        ]),
      );
}

class _ResolvedLine extends StatelessWidget {
  final WaterIncident incident;
  const _ResolvedLine({required this.incident});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.sprout),
        const SizedBox(width: AppTheme.s2),
        Expanded(
          child: Text(
              'Last request resolved at ${clockText(incident.resolvedAt ?? incident.openedAt)}. '
              '${plural(incident.trucks, 'truck')} delivered.',
              style: AppTheme.footnote.copyWith(color: AppTheme.sprout)),
        ),
      ]);
}

class _HelpCard extends StatelessWidget {
  final WaterZone zone;
  final WaterIncident? incident;
  final WaterIncident? resolved;
  final bool voted;
  final VoidCallback onAsk;
  const _HelpCard({
    required this.zone,
    required this.incident,
    required this.resolved,
    required this.voted,
    required this.onAsk,
  });

  String get _headline {
    final i = incident;
    if (i == null) return 'Be the first to ask';
    return switch (i.stage) {
      IncidentStage.open => '${plural(i.threshold - i.votes, 'more voice')} needed',
      IncidentStage.requested => 'Your request is with ${zone.provider}',
      IncidentStage.acknowledged => '${zone.provider} has seen your request',
      IncidentStage.dispatched => 'Help is on the way',
      IncidentStage.resolved => 'Resolved',
    };
  }

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final threshold = i?.threshold ?? zone.voteThreshold;
    final dispatched = i?.stage == IncidentStage.dispatched;
    // The shared backend only counts a vote while the request is open or newly sent.
    final canVote = i == null || i.stage.index <= IncidentStage.requested.index;
    final color = dispatched ? AppTheme.sprout : zone.status.color;
    return GlassCard(
      tint: color.withValues(alpha: 0.10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RingGauge(
            value: i?.progress ?? 0,
            size: 96,
            color: color,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              CountUp((i?.votes ?? 0).toDouble(), prefix: '', style: AppTheme.title2),
              Text('of $threshold', style: AppTheme.caption),
            ]),
          ),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_headline, style: AppTheme.headline),
              const SizedBox(height: 2),
              Text(
                  '${threshold == 1 ? 'When 1 neighbour asks' : 'When $threshold neighbours ask'}, '
                  'the request goes to ${zone.provider}. Each person counts once.',
                  style: AppTheme.footnote),
            ]),
          ),
        ]),
        if (dispatched) ...[
          const SizedBox(height: AppTheme.s4),
          _DispatchBanner(incident: i!, provider: zone.provider),
        ],
        if (resolved != null && i == null) ...[
          const SizedBox(height: AppTheme.s3),
          _ResolvedLine(incident: resolved!),
        ],
        if (canVote) ...[
          const SizedBox(height: AppTheme.s4),
          voted
              ? const GlassButton(label: 'You asked for help', icon: Icons.check_circle_rounded)
              : GlassButton(label: 'Ask for water help', icon: Icons.front_hand_rounded, onPressed: onAsk),
        ],
        const SizedBox(height: AppTheme.s4),
        IncidentTimeline(incident: i),
      ]),
    );
  }
}

class _DispatchBanner extends StatelessWidget {
  final WaterIncident incident;
  final String provider;
  const _DispatchBanner({required this.incident, required this.provider});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppTheme.s4),
        decoration: BoxDecoration(
          color: AppTheme.sprout.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.sprout.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🚛', style: TextStyle(fontSize: 30)),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text('${plural(incident.trucks, 'truck')} on the way', style: AppTheme.title3)),
          ]),
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            Expanded(child: StatTile(label: 'Trucks', value: '${incident.trucks}', color: AppTheme.sprout)),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: StatTile(label: 'ETA', value: '${incident.etaMinutes} min', color: AppTheme.sprout)),
          ]),
          const SizedBox(height: AppTheme.s2),
          _EtaCaption(incident: incident),
          if (incident.note.isNotEmpty) ...[
            const SizedBox(height: AppTheme.s3),
            Text('Note from $provider', style: AppTheme.caption),
            Text(incident.note, style: AppTheme.body),
          ],
        ]),
      );
}

/// "About 85 min left", re-worked every half minute while the page is open.
class _EtaCaption extends StatefulWidget {
  final WaterIncident incident;
  const _EtaCaption({required this.incident});

  @override
  State<_EtaCaption> createState() => _EtaCaptionState();
}

class _EtaCaptionState extends State<_EtaCaption> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    final sent = i.dispatchedAt ?? DateTime.now();
    final left = i.etaMinutes - DateTime.now().difference(sent).inMinutes;
    return Text(
        '${left > 0 ? 'About $left min left' : 'Due about now'}. Sent at ${clockText(sent)}.',
        style: AppTheme.footnote);
  }
}

// -------------------------------------------------------------- prepare

const _checklist = [
  'Fill every container now',
  'Keep drinking water separate from washing water',
  'Delay washing and irrigation',
  'Check on neighbours who cannot carry water',
];

const _tankChips = [0, 500, 1000, 2500, 5000];

class _PrepareSection extends ConsumerWidget {
  final WaterForecast forecast;
  final Set<int> ticked;
  final void Function(int) onTick;
  const _PrepareSection({required this.forecast, required this.ticked, required this.onTick});

  void _order(BuildContext context, WidgetRef ref, int bottles) {
    HapticFeedback.mediumImpact();
    // Make the cart hold exactly the number on the button, up or down, so
    // tapping twice never orders twice and checkout never shows another count.
    final market = ref.read(marketProvider.notifier);
    final have = ref.read(marketProvider).cart['p-water'] ?? 0;
    if (bottles > have) market.add('p-water', bottles - have);
    for (var n = have; n > bottles; n--) {
      market.remove('p-water');
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(waterProvider.select((s) => s.prefs));
    final store = ref.read(waterProvider.notifier);
    final water = ref.watch(marketProvider.select(
        (m) => m.products.where((p) => p.id == 'p-water' && p.buyable).firstOrNull));
    final plan = planWater(prefs: prefs, forecast: forecast);
    final covered = plan.bottles == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('🪣', 'If it runs dry'),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tell us about your home and we work out what to put away.', style: AppTheme.callout),
          const SizedBox(height: AppTheme.s4),
          _InputRow(
            icon: Icons.groups_rounded,
            label: 'People at home',
            stepper: AmountStepper(
              value: '${prefs.household}',
              subject: 'people',
              onMinus: prefs.household > 1 ? () => store.setHousehold(prefs.household - 1) : null,
              onPlus: () => store.setHousehold(prefs.household + 1),
            ),
          ),
          const SizedBox(height: AppTheme.s3),
          _InputRow(
            icon: Icons.propane_tank_rounded,
            label: 'Water stored',
            stepper: AmountStepper(
              value: '${groupDigits(prefs.tankLitres)} L',
              subject: 'water stored',
              onMinus: prefs.tankLitres > 0 ? () => store.setTank(prefs.tankLitres - 250) : null,
              onPlus: () => store.setTank(prefs.tankLitres + 250),
            ),
          ),
          const SizedBox(height: AppTheme.s3),
          Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
            for (final v in _tankChips)
              WaterChip(
                label: '${groupDigits(v)} L',
                selected: prefs.tankLitres == v,
                onTap: () => store.setTank(v),
              ),
          ]),
          if (prefs.herd > 0) ...[
            const SizedBox(height: AppTheme.s4),
            Row(children: [
              const Text('🐄', style: TextStyle(fontSize: 20)),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                child: Text(
                    'Livestock: ${prefs.herd} head need ${groupDigits(prefs.herd * litresPerCattlePerDay)} L a day',
                    style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
              ),
            ]),
          ],
          const SizedBox(height: AppTheme.s4),
          const Divider(),
          const SizedBox(height: AppTheme.s4),
          Row(children: [
            Expanded(child: StatTile(label: 'You use', value: '${groupDigits(plan.litresPerDay)} L a day')),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: StatTile(
                label: 'Stored water lasts',
                value: plan.daysOfCover == 1 ? '1.0 day' : '${plan.daysOfCover.toStringAsFixed(1)} days',
              ),
            ),
          ]),
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            Expanded(child: StatTile(label: 'Planning for', value: '${plan.daysToCover} days')),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: StatTile(
                label: 'Short by',
                value: '${groupDigits(plan.shortfallLitres)} L',
                color: covered ? AppTheme.ok : AppTheme.warn,
              ),
            ),
          ]),
          const SizedBox(height: AppTheme.s4),
          if (covered)
            _Covered(prefs: prefs, plan: plan)
          else if (water != null) ...[
            GlassButton(
              label: 'Order ${plan.bottles} water ${plan.bottles == 1 ? 'bottle' : 'bottles'}',
              icon: Icons.local_shipping_rounded,
              onPressed: () => _order(context, ref, plan.bottles),
            ),
            const SizedBox(height: AppTheme.s2),
            Text(
                '${plan.bottles} x $bottleLitres L = ${groupDigits(plan.bottles * bottleLitres)} L for '
                '${rand(plan.bottles * water.price)}, delivered by a neighbour.',
                style: AppTheme.caption),
          ] else
            Text('Drinking water is not on sale in your area yet. Store what you can and check on your neighbours.',
                style: AppTheme.footnote),
        ]),
      ),
      const SizedBox(height: AppTheme.s3),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Before it runs dry', style: AppTheme.headline),
          const SizedBox(height: AppTheme.s2),
          for (var i = 0; i < _checklist.length; i++)
            _CheckItem(text: _checklist[i], ticked: ticked.contains(i), onTap: () => onTick(i)),
        ]),
      ),
    ]);
  }
}

class _InputRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget stepper;
  const _InputRow({required this.icon, required this.label, required this.stepper});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: AppTheme.s3),
        Expanded(child: Text(label, style: AppTheme.body)),
        stepper,
      ]);
}

class _Covered extends StatelessWidget {
  final WaterPrefs prefs;
  final WaterPlan plan;
  const _Covered({required this.prefs, required this.plan});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppTheme.s4),
        decoration: BoxDecoration(
          color: AppTheme.sprout.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.sprout.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.sprout),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You are covered', style: AppTheme.headline),
              Text(
                  '${groupDigits(prefs.tankLitres)} L lasts ${plan.daysOfCover.toStringAsFixed(1)} days, '
                  'enough for the ${plan.daysToCover} days we plan for.',
                  style: AppTheme.footnote),
            ]),
          ),
        ]),
      );
}

class _CheckItem extends StatelessWidget {
  final String text;
  final bool ticked;
  final VoidCallback onTap;
  const _CheckItem({required this.text, required this.ticked, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        checked: ticked,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.s2),
            child: Row(children: [
              Icon(ticked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 22, color: ticked ? AppTheme.sprout : AppTheme.textTertiary),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: Text(text,
                    style: AppTheme.subhead.copyWith(
                      color: ticked ? AppTheme.textTertiary : AppTheme.textPrimary,
                      decoration: ticked ? TextDecoration.lineThrough : null,
                    )),
              ),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------ provider + demo

class _ProviderEntry extends StatelessWidget {
  const _ProviderEntry();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppTheme.s6),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🧰', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: AppTheme.s3),
              Expanded(child: Text('Water provider tools', style: AppTheme.title3)),
            ]),
            const SizedBox(height: AppTheme.s2),
            Text('Answer community requests and publish reservoir readings.', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s3),
            GhostButton(
              label: 'Open provider desk',
              icon: Icons.support_agent_rounded,
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderDeskScreen())),
            ),
          ]),
        ),
      );
}

class _DemoControls extends ConsumerWidget {
  final WaterState state;
  const _DemoControls({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(waterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.s6),
      child: GlassCard(
        tint: AppTheme.warn.withValues(alpha: 0.10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🧪', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text('Demo controls', style: AppTheme.title3)),
            Pill('Simulated', color: AppTheme.warn),
          ]),
          const SizedBox(height: AppTheme.s2),
          Text(
              'Neighbours and the water provider are simulated here. Nothing you do reaches a real provider.',
              style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s4),
          GlassButton(
            label: state.dryRunning ? 'Draining the reservoir' : 'Run dry spell',
            icon: Icons.water_drop_outlined,
            onPressed: state.dryRunning
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    store.runDrySpell(zoneId: state.myZone?.id ?? 'umlazi');
                  },
          ),
          if (state.dryRunning) ...[
            const SizedBox(height: AppTheme.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(minHeight: 6, color: AppTheme.warn, backgroundColor: AppTheme.glassFillStrong),
            ),
          ],
          const SizedBox(height: AppTheme.s3),
          GhostButton(
            label: 'Reset demo',
            icon: Icons.restart_alt_rounded,
            onPressed: () {
              HapticFeedback.mediumImpact();
              store.resetDemo();
            },
          ),
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            Expanded(child: Text('Pretend provider answers by itself', style: AppTheme.callout)),
            Switch(value: state.autopilot, activeThumbColor: AppTheme.sprout, onChanged: store.setAutopilot),
          ]),
        ]),
      ),
    );
  }
}


// --------------------------------------------------------- where it comes from

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}

String _every(Duration d) {
  if (d.inMinutes < 90) return 'about every ${d.inMinutes.clamp(1, 90)} minutes';
  if (d.inHours < 36) return 'about every ${d.inHours} hours';
  return 'about every ${d.inDays} days';
}

/// Answers the questions a sceptic should ask of the water radar: where the
/// numbers come from, how fresh they are, who responds, and what happens when
/// nobody does.
class _SourceCard extends StatelessWidget {
  final WaterState state;
  final WaterZone zone;
  const _SourceCard({required this.state, required this.zone});

  Widget _row(String q, String a) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q, style: AppTheme.footnote.copyWith(color: AppTheme.sprout, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(a, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final r = zone.readings;
    final last = r.isEmpty ? null : r.last.at;
    final gap = r.length < 2 ? null : r.last.at.difference(r[r.length - 2].at);
    final answered = state.incidents.any((i) =>
        i.zoneId == zone.id && (i.stage == IncidentStage.acknowledged || i.stage == IncidentStage.dispatched));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('🔎', 'Where this comes from'),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(
              'Who measures it',
              zone.source != null
                  ? '${zone.provider}. Source: ${zone.source}. These are real dam levels from the Department of Water and Sanitation. A healthy dam does not mean every tap is running, so local reports and votes still matter.'
                  : zone.demo || state.demo
                  ? '${zone.provider}. In this demo the readings are simulated and labelled as demo. In production the provider publishes real reservoir readings.'
                  : '${zone.provider} publishes the reservoir readings for ${zone.name}. We do not invent or scrape numbers.'),
          _row(
              'How fresh it is',
              last == null
                  ? 'No reading yet. The forecast stays blank until the provider publishes one.'
                  : 'Last reading ${_ago(last)}${gap == null ? '' : ', updated ${_every(gap)}'}. The forecast is statistical and shows its confidence.'),
          _row(
              'Who responds',
              answered
                  ? '${zone.provider} has answered a request here. Their update shows in this page and in the community.'
                  : 'The provider acknowledges requests and sends trucks. Farms with a borehole or tanker can also answer through Nolifa Grow.'),
          _row(
              'If nobody responds',
              'Your votes still count and stay visible, so a request that is ignored is public. Meanwhile the planner below tells you how many 25 L bottles close the gap, neighbours can deliver them, and nearby farm suppliers can step in.'),
        ]),
      ),
    ]);
  }
}


// ------------------------------------------------------------- real levels

final _realLevelsProvider = FutureProvider<List<FeedZone>>((ref) async {
  final feed = ref.watch(waterFeedProvider);
  if (feed == null) return <FeedZone>[];
  return feed.load();
});

/// Real reservoir levels from the Department of Water and Sanitation. The
/// supply system nearest where the phone really is comes first and is marked.
class RealDamLevels extends ConsumerWidget {
  const RealDamLevels({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_realLevelsProvider);
    final loc = ref.watch(userLocationProvider).valueOrNull;
    final mine = loc == null ? null : nearestSystem(loc.$1, loc.$2);
    final outside = loc != null && mine == null;
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('🌍', 'Real dam levels today'),
        GlassCard(
          child: async.when(
            loading: () => Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.sprout)),
              const SizedBox(width: AppTheme.s3),
              Text('Fetching the latest report', style: AppTheme.callout),
            ]),
            error: (_, __) => Text('Could not reach the Department of Water and Sanitation.', style: AppTheme.callout),
            data: (all) {
              final zones = [...all]..sort((a, b) => (b.zone.id == mine?.id ? 1 : 0).compareTo(a.zone.id == mine?.id ? 1 : 0));
              return zones.isEmpty
                ? Text('No real readings available right now.', style: AppTheme.callout)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(zones.first.zone.source ?? '', style: AppTheme.caption),
                    if (outside)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTheme.s2),
                        child: Text('You are outside KwaZulu-Natal. Real dam data for your province is not in the app yet, so these are the KwaZulu-Natal dams.',
                            style: AppTheme.footnote.copyWith(color: AppTheme.warn)),
                      ),
                    if (loc == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTheme.s2),
                        child: Text('Turn on location to see the dams that supply where you are.', style: AppTheme.footnote),
                      ),
                    const SizedBox(height: AppTheme.s2),
                    for (final f in zones)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(child: Text(f.zone.name, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
                                if (f.zone.id == mine?.id) ...[const SizedBox(width: 6), Pill('Near you', color: AppTheme.sprout)],
                              ]),
                              Text(f.forecast.changePerDay.abs() < 0.05 ? 'Steady this week' : '${f.forecast.changePerDay < 0 ? 'Falling' : 'Rising'} ${f.forecast.changePerDay.abs().toStringAsFixed(2)} points a day',
                                  style: AppTheme.caption),
                            ]),
                          ),
                          Pill('${f.zone.level.toStringAsFixed(1)}%', color: f.zone.status.color),
                        ]),
                      ),
                    const SizedBox(height: AppTheme.s1),
                    Text(
                        'These are bulk supply dams, updated weekly. A healthy dam does not mean every tap is running: local outages come from pipes and pumps, which is what community reports and votes are for.',
                        style: AppTheme.caption),
                  ]);
            },
          ),
        ),
      ]),
    );
  }
}
