import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'water_models.dart';
import 'water_store.dart';
import 'water_widgets.dart';

import '../tr_text.dart' show Text;
/// What the water provider sees: requests that reached the threshold, and the
/// controls to answer them.
class ProviderDeskScreen extends StatelessWidget {
  const ProviderDeskScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Column(children: [
              WaterBackRow(),
              Expanded(child: _DeskView()),
            ]),
          ),
        ),
      );
}

class _DeskView extends ConsumerWidget {
  const _DeskView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(waterProvider);
    final sections = <(String, Widget)>[
      if (!ref.read(waterProvider.notifier).isProvider)
        ('locked', const _NotProviderCard())
      else ...[
        ('queue', _QueueSection(state: s)),
        ('road', _RoadSection(state: s)),
        ('zones', _ZonesSection(zones: s.zones, state: s)),
        ('publish', _PublishSection(zones: s.zones)),
        if (!s.demo) ('add', _AddCommunitySection(zones: s.zones)),
      ],
    ];
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '🧰',
            title: 'Provider desk',
            subtitle: 'Answer requests and keep readings current',
            accent: AppTheme.sprout,
            trailing: s.demo ? Pill('Demo', color: AppTheme.warn, icon: Icons.science_rounded) : null,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, AppTheme.s10),
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

class _NotProviderCard extends StatelessWidget {
  const _NotProviderCard();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppTheme.s6),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🔒', style: const TextStyle(fontSize: 34)),
            const SizedBox(height: AppTheme.s2),
            Text('This desk is for the water provider', style: AppTheme.title3),
            const SizedBox(height: AppTheme.s2),
            Text(
                'Your account does not have provider access. To follow your own community\'s request, '
                'open the Water page.',
                style: AppTheme.callout),
          ]),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  const _EmptyCard(this.emoji, this.title, this.body);

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.headline),
              const SizedBox(height: 2),
              Text(body, style: AppTheme.footnote),
            ]),
          ),
        ]),
      );
}

WaterZone? _zoneOf(Iterable<WaterZone> zones, String id) {
  for (final z in zones) {
    if (z.id == id) return z;
  }
  return null;
}

// Firestore rules refuse longer text. Stopping it at the form is kinder than
// a write that fails after the provider has pressed the button.
const _maxText = 80; // community name, provider, reservoir
const _maxNote = 280; // dispatch note
const _maxVotes = 100000; // votes needed

/// Runs a provider write. False means it was refused, so the desk can say so
/// instead of reporting trucks sent that the community never sees.
Future<bool> _tryWrite(String what, Future<void> Function() write) async {
  try {
    await write();
    return true;
  } catch (e) {
    debugPrint('water: could not $what: $e');
    return false;
  }
}

String _refused(String what) => 'Could not $what. Check your permission and connection.';

/// [_tryWrite] for a button with no form: a refusal shows in a snackbar.
Future<bool> _writeOrWarn(BuildContext context, String what, Future<void> Function() write) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await _tryWrite(what, write);
  if (!ok) messenger?.showSnackBar(SnackBar(content: Text(_refused(what))));
  return ok;
}

// ---------------------------------------------------------------- queue

class _QueueSection extends StatelessWidget {
  final WaterState state;
  const _QueueSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final queue = state.providerQueue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('📥', 'Needs an answer',
          trailing: queue.isEmpty ? null : Pill('${queue.length}', color: AppTheme.warn)),
      if (queue.isEmpty)
        const _EmptyCard('✅', 'Nothing waiting',
            'Requests show up here once a community reaches its vote threshold.')
      else
        for (final i in queue)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s3),
            child: _RequestCard(incident: i, zone: _zoneOf(state.zones, i.zoneId)),
          ),
    ]);
  }
}

class _RequestCard extends ConsumerWidget {
  final WaterIncident incident;
  final WaterZone? zone;
  const _RequestCard({required this.incident, required this.zone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = incident;
    final name = zone?.name ?? i.zoneId;
    final waiting = i.stage == IncidentStage.requested;
    return GlassCard(
      tint: waiting ? AppTheme.warn.withValues(alpha: 0.10) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: AppTheme.headline)),
          Pill(i.stage.label,
              color: waiting ? AppTheme.warn : AppTheme.sprout,
              icon: waiting ? Icons.mark_email_unread_rounded : Icons.visibility_rounded),
        ]),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(child: StatTile(label: 'People asked', value: '${i.votes} of ${i.threshold} needed')),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: StatTile(
              label: 'People served',
              value: zone == null ? 'Unknown' : groupDigits(zone!.population),
            ),
          ),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text('Reached the provider ${agoText(i.requestedAt ?? i.openedAt)}', style: AppTheme.caption),
        const SizedBox(height: AppTheme.s3),
        GlassButton(
          label: 'Send trucks',
          icon: Icons.local_shipping_rounded,
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _DispatchSheet(incident: i, zoneName: name),
          ),
        ),
        if (waiting) ...[
          const SizedBox(height: AppTheme.s2),
          Center(
            child: GhostButton(
              label: 'Acknowledge',
              icon: Icons.visibility_rounded,
              onPressed: () {
                HapticFeedback.mediumImpact();
                final store = ref.read(waterProvider.notifier);
                _writeOrWarn(context, 'acknowledge', () => store.acknowledge(i.id));
              },
            ),
          ),
        ],
      ]),
    );
  }
}

class _DispatchSheet extends ConsumerStatefulWidget {
  final WaterIncident incident;
  final String zoneName;
  const _DispatchSheet({required this.incident, required this.zoneName});

  @override
  ConsumerState<_DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends ConsumerState<_DispatchSheet> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  int _trucks = 2;
  int _eta = 60;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? _noteLength(String? v) =>
      (v ?? '').trim().length > _maxNote ? 'Keep the note to $_maxNote characters or fewer' : null;

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(waterProvider.notifier);
    final sent = await _tryWrite(
        'send trucks',
        () => store.dispatch(widget.incident.id, trucks: _trucks, etaMinutes: _eta, note: _note.text.trim()));
    if (!mounted) return;
    if (sent) {
      Navigator.pop(context);
    } else {
      // Stay open: closing now would tell the provider trucks are coming when nobody will see them.
      setState(() {
        _busy = false;
        _error = _refused('send');
      });
    }
  }

  @override
  Widget build(BuildContext context) => WaterSheet(
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🚛 Send trucks to ${widget.zoneName}', style: AppTheme.title2),
            const SizedBox(height: 4),
            Text('The community sees how many trucks are coming and when.', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s5),
            Row(children: [
              Expanded(child: Text('Trucks', style: AppTheme.body)),
              AmountStepper(
                value: '$_trucks',
                subject: 'trucks',
                onMinus: _trucks > 1 ? () => setState(() => _trucks--) : null,
                onPlus: _trucks < 10 ? () => setState(() => _trucks++) : null,
              ),
            ]),
            const SizedBox(height: AppTheme.s3),
            Row(children: [
              Expanded(child: Text('Arrives in', style: AppTheme.body)),
              AmountStepper(
                value: '$_eta min',
                subject: 'arrival time',
                onMinus: _eta > 15 ? () => setState(() => _eta -= 15) : null,
                onPlus: _eta < 240 ? () => setState(() => _eta += 15) : null,
              ),
            ]),
            const SizedBox(height: AppTheme.s4),
            GlassField(
              key: const ValueKey('dispatch-note'),
              controller: _note,
              label: 'Note for the community (optional)',
              icon: Icons.edit_note_rounded,
              validator: _noteLength,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppTheme.s5),
            if (_error != null) ...[
              Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
              const SizedBox(height: AppTheme.s2),
            ],
            GlassButton(
              label: 'Send ${plural(_trucks, 'truck')} now',
              icon: Icons.local_shipping_rounded,
              busy: _busy,
              onPressed: _send,
            ),
          ]),
        ),
      );
}

// ----------------------------------------------------------------- road

class _RoadSection extends ConsumerWidget {
  final WaterState state;
  const _RoadSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final road = state.inTransit;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('🚛', 'On the road',
          trailing: road.isEmpty ? null : Pill('${road.length}', color: AppTheme.sprout)),
      if (road.isEmpty)
        const _EmptyCard('🛣️', 'No trucks on the road', 'Trucks you send show up here until you mark them delivered.')
      else
        for (final i in road)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s3),
            child: GlassCard(
              tint: AppTheme.sprout.withValues(alpha: 0.10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_zoneOf(state.zones, i.zoneId)?.name ?? i.zoneId, style: AppTheme.headline)),
                  Pill(plural(i.trucks, 'truck'), color: AppTheme.sprout, icon: Icons.local_shipping_rounded),
                ]),
                const SizedBox(height: AppTheme.s3),
                Row(children: [
                  Expanded(child: StatTile(label: 'ETA', value: '${i.etaMinutes} min')),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(child: StatTile(label: 'Sent', value: agoText(i.dispatchedAt))),
                ]),
                if (i.note.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.s3),
                  Text(i.note, style: AppTheme.callout),
                ],
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                  label: 'Mark delivered',
                  icon: Icons.check_circle_rounded,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    final store = ref.read(waterProvider.notifier);
                    _writeOrWarn(context, 'mark delivered', () => store.resolve(i.id));
                  },
                ),
              ]),
            ),
          ),
    ]);
  }
}

// ---------------------------------------------------------------- zones

class _ZonesSection extends StatelessWidget {
  final List<WaterZone> zones;
  final WaterState state;
  const _ZonesSection({required this.zones, required this.state});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('🗺️', 'Communities'),
        if (zones.isEmpty)
          const _EmptyCard('🏘️', 'No communities yet', 'Add a community below to start publishing readings.')
        else
          for (final z in zones)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.s3),
              child: _ZoneRow(zone: z, forecast: state.forecastOf(z.id)),
            ),
      ]);
}

class _ZoneRow extends StatelessWidget {
  final WaterZone zone;
  final WaterForecast? forecast;
  const _ZoneRow({required this.zone, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(zone.name, style: AppTheme.headline),
            if (f != null)
              Text(forecastHeadline(f), style: AppTheme.footnote.copyWith(color: forecastColor(f))),
            Text('${groupDigits(zone.population)} people  •  updated ${agoText(zone.updated)}',
                style: AppTheme.caption),
          ]),
        ),
        const SizedBox(width: AppTheme.s3),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${zone.level.round()}%', style: AppTheme.title2.copyWith(color: zone.status.color)),
          const SizedBox(height: 2),
          Pill(zone.status.label, color: zone.status.color),
        ]),
      ]),
    );
  }
}

// -------------------------------------------------------------- publish

class _PublishSection extends ConsumerStatefulWidget {
  final List<WaterZone> zones;
  const _PublishSection({required this.zones});

  @override
  ConsumerState<_PublishSection> createState() => _PublishSectionState();
}

class _PublishSectionState extends ConsumerState<_PublishSection> {
  String? _zoneId;
  double? _level; // null until the slider is moved: follows the community's own level
  bool _busy = false;

  Future<void> _publish(WaterZone zone, double level) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final store = ref.read(waterProvider.notifier);
    setState(() => _busy = true);
    final ok = await _tryWrite('publish', () => store.publishReading(zone.id, level));
    messenger?.showSnackBar(
        SnackBar(content: Text(ok ? 'Published ${level.round()}% for ${zone.name}' : _refused('publish'))));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _level = null; // after a refusal keep the level, so it can be tried again
    });
  }

  @override
  Widget build(BuildContext context) {
    final zone = _zoneOf(widget.zones, _zoneId ?? '') ?? widget.zones.firstOrNull;
    final level = _level ?? zone?.level ?? 0;
    final color = WaterStatusX.of(level).color;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('📤', 'Publish a reading'),
      GlassCard(
        child: zone == null
            ? Text('Add a community first. Then you can publish its reservoir level here.',
                style: AppTheme.callout)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                  for (final z in widget.zones)
                    WaterChip(
                      label: z.name,
                      selected: z.id == zone.id,
                      dot: z.status.color,
                      onTap: () => setState(() {
                        _zoneId = z.id;
                        _level = null;
                      }),
                    ),
                ]),
                const SizedBox(height: AppTheme.s4),
                Row(children: [
                  Expanded(child: Text('Reservoir level', style: AppTheme.body)),
                  Text('${level.round()}%', style: AppTheme.title2.copyWith(color: color)),
                ]),
                Slider(
                  value: level.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${level.round()}%',
                  activeColor: color,
                  onChanged: (v) => setState(() => _level = v),
                ),
                Text(
                    'Now ${zone.level.round()}%. A new reading updates the status and the forecast '
                    'for everyone in ${zone.name}.',
                    style: AppTheme.caption),
                const SizedBox(height: AppTheme.s4),
                GlassButton(
                  label: 'Publish',
                  icon: Icons.upload_rounded,
                  busy: _busy,
                  onPressed: () => _publish(zone, level),
                ),
              ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ add zone

class _AddCommunitySection extends StatelessWidget {
  final List<WaterZone> zones;
  const _AddCommunitySection({required this.zones});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('➕', 'Add a community'),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'A new community starts with one reading and says "Not enough readings yet" '
                'until you publish more.',
                style: AppTheme.callout),
            const SizedBox(height: AppTheme.s3),
            GhostButton(
              label: 'Add community',
              icon: Icons.add_location_alt_rounded,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _AddCommunitySheet(existing: zones),
              ),
            ),
          ]),
        ),
      ]);
}

class _AddCommunitySheet extends ConsumerStatefulWidget {
  final List<WaterZone> existing;
  const _AddCommunitySheet({required this.existing});

  @override
  ConsumerState<_AddCommunitySheet> createState() => _AddCommunitySheetState();
}

class _AddCommunitySheetState extends ConsumerState<_AddCommunitySheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _provider = TextEditingController(text: widget.existing.firstOrNull?.provider ?? '');
  final _reservoir = TextEditingController();
  final _people = TextEditingController();
  final _votes = TextEditingController(text: '25');
  double _level = 60;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _provider, _reservoir, _people, _votes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _short(String? v) => (v ?? '').trim().length > _maxText ? 'Use $_maxText characters or fewer' : null;

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : _short(v);

  String? _positive(String? v) {
    final n = int.tryParse((v ?? '').replaceAll(' ', ''));
    return n == null || n < 1 ? 'Enter a number above 0' : null;
  }

  String? _votesNeeded(String? v) {
    final n = int.tryParse((v ?? '').replaceAll(' ', ''));
    return n == null || n < 1 || n > _maxVotes ? 'Enter a number from 1 to ${groupDigits(_maxVotes)}' : null;
  }

  /// A readable id from the name, never one that would overwrite a community.
  String _idFor(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final root = slug.isEmpty ? 'community' : slug;
    final taken = {for (final z in widget.existing) z.id};
    var id = root;
    for (var n = 2; taken.contains(id); n++) {
      id = '$root-$n';
    }
    return id;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final reservoir = _reservoir.text.trim();
    final zone = WaterZone(
      id: _idFor(name),
      name: name,
      provider: _provider.text.trim(),
      reservoir: reservoir.isNotEmpty ? reservoir : ('$name Reservoir'.length <= _maxText ? '$name Reservoir' : name),
      population: int.parse(_people.text.replaceAll(' ', '')),
      voteThreshold: int.parse(_votes.text.replaceAll(' ', '')),
      readings: [WaterReading(DateTime.now(), _level)],
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(waterProvider.notifier).upsertZone(zone);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(content: Text('$name added')));
    } catch (e) {
      debugPrint('water: could not add community: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save. Check your connection and permission, then try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => WaterSheet(
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🏘️ Add a community', style: AppTheme.title2),
            const SizedBox(height: 4),
            Text('The radar needs at least 4 readings before it forecasts.', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s4),
            GlassField(
              key: const ValueKey('add-name'),
              controller: _name,
              label: 'Community name',
              icon: Icons.place_rounded,
              validator: _required,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppTheme.s3),
            GlassField(
              key: const ValueKey('add-provider'),
              controller: _provider,
              label: 'Water provider',
              icon: Icons.business_rounded,
              validator: _required,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppTheme.s3),
            GlassField(
              key: const ValueKey('add-reservoir'),
              controller: _reservoir,
              label: 'Reservoir (optional)',
              icon: Icons.water_rounded,
              validator: _short,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppTheme.s3),
            GlassField(
              key: const ValueKey('add-people'),
              controller: _people,
              label: 'People served',
              icon: Icons.groups_rounded,
              keyboardType: TextInputType.number,
              validator: _positive,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppTheme.s3),
            GlassField(
              key: const ValueKey('add-votes'),
              controller: _votes,
              label: 'Votes needed to reach you',
              icon: Icons.how_to_vote_rounded,
              keyboardType: TextInputType.number,
              validator: _votesNeeded,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppTheme.s4),
            Row(children: [
              Expanded(child: Text('Starting level', style: AppTheme.body)),
              Text('${_level.round()}%',
                  style: AppTheme.title3.copyWith(color: WaterStatusX.of(_level).color)),
            ]),
            Slider(
              key: const ValueKey('add-level'),
              value: _level,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_level.round()}%',
              activeColor: WaterStatusX.of(_level).color,
              onChanged: (v) => setState(() => _level = v),
            ),
            if (_error != null) ...[
              Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
              const SizedBox(height: AppTheme.s2),
            ],
            const SizedBox(height: AppTheme.s2),
            GlassButton(
              label: 'Add community',
              icon: Icons.add_rounded,
              busy: _busy,
              onPressed: _save,
            ),
          ]),
        ),
      );
}
