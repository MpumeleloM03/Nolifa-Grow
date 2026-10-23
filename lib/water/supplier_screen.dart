import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        IncidentStage,
        IncidentStageX,
        Pill,
        ProviderDeskScreen,
        Reveal,
        SectionTitle,
        WaterIncident,
        WaterZone,
        marketProvider,
        waterProvider;
import '../store/store_common.dart' show SheetFrame, groupDigits, timeAgo;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'supplier_store.dart';

const _blue = Color(0xFF5AB8F0);

/// Water provider for farmers: a farm with a borehole or a tanker registers,
/// sees which communities are asking for water, and offers help.
class WaterSupplierScreen extends ConsumerWidget {
  const WaterSupplierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sup = ref.watch(supplierProvider);
    final store = ref.read(supplierProvider.notifier);
    final w = ref.watch(waterProvider);
    final s = sup.supplier;
    final farm = ref.watch(marketProvider.select((m) => m.profile.farmName));
    final asking = [
      for (final i in w.incidents)
        if (i.stage != IncidentStage.resolved) i
    ]..sort((a, b) => b.votes.compareTo(a.votes));

    return Scaffold(
      body: AppBackdrop(
        tint: _blue,
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
                title: const Text('Water provider'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Help a community get water', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text(
                      'Got a borehole, a dam or a tanker? Tell communities what you can spare. When one asks for help, you can answer.',
                      style: AppTheme.callout),
                  const SizedBox(height: AppTheme.s4),
                  GlassCard(
                    tint: _blue.withValues(alpha: 0.10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: _blue,
                        title: Text('I can supply water', style: AppTheme.headline),
                        subtitle: Text(
                            s.enabled ? 'Communities in ${s.radiusKm} km can see your offer.' : 'Switch on to register your farm as a supplier.',
                            style: AppTheme.footnote),
                        value: s.enabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          store.update(s.copyWith(enabled: v));
                        },
                      ),
                      if (s.enabled) ...[
                        const SizedBox(height: AppTheme.s2),
                        Text('Source', style: AppTheme.footnote),
                        const SizedBox(height: AppTheme.s1),
                        Wrap(spacing: AppTheme.s2, children: [
                          for (final o in const ['Borehole', 'Tanker truck', 'Dam or river', 'Rain tanks'])
                            ChoiceChip(
                              label: Text(o),
                              selected: s.source == o,
                              onSelected: (_) => store.update(s.copyWith(source: o)),
                            ),
                        ]),
                        _stepper('Litres a day you can spare', groupDigits(s.litresPerDay),
                            () => store.update(s.copyWith(litresPerDay: (s.litresPerDay - 1000).clamp(500, 200000))),
                            () => store.update(s.copyWith(litresPerDay: (s.litresPerDay + 1000).clamp(500, 200000)))),
                        _stepper('How far you can reach (km)', '${s.radiusKm}',
                            () => store.update(s.copyWith(radiusKm: (s.radiusKm - 5).clamp(5, 200))),
                            () => store.update(s.copyWith(radiusKm: (s.radiusKm + 5).clamp(5, 200)))),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: _blue,
                          title: Text('I can deliver it', style: AppTheme.body),
                          value: s.canDeliver,
                          onChanged: (v) => store.update(s.copyWith(canDeliver: v)),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: _blue,
                          title: Text(s.free ? 'Free to the community' : 'At cost (fuel and time)', style: AppTheme.body),
                          value: s.free,
                          onChanged: (v) => store.update(s.copyWith(free: v)),
                        ),
                      ],
                    ]),
                  ),
                  if (s.enabled) ...[
                    SectionTitle('🚰', 'Communities asking for water',
                        trailing: asking.isEmpty ? null : Pill('${asking.length}', color: _blue)),
                    if (asking.isEmpty)
                      GlassCard(
                          child: Text('No community is asking right now. When one reaches its vote target you see it here.',
                              style: AppTheme.callout))
                    else
                      for (var i = 0; i < asking.length; i++)
                        Reveal(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s3),
                            child: _Request(asking[i], w.zones.where((z) => z.id == asking[i].zoneId).firstOrNull, farm.isEmpty ? 'A local farm' : farm),
                          ),
                        ),
                    if (sup.offers.isNotEmpty) ...[
                      SectionTitle('🤝', 'Your help so far', trailing: Pill('${groupDigits(sup.litresGiven)} L', color: AppTheme.sprout)),
                      for (final o in sup.offers.take(6))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s2),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                            child: Row(children: [
                              const Text('💧', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: AppTheme.s3),
                              Expanded(child: Text('${o.zoneName}: ${groupDigits(o.litres)} L, about ${o.etaMinutes} min', style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary))),
                              Text(timeAgo(o.at), style: AppTheme.caption),
                            ]),
                          ),
                        ),
                    ],
                    const SizedBox(height: AppTheme.s3),
                    GhostButton(
                      label: 'Open the provider desk',
                      icon: Icons.dashboard_customize_rounded,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderDeskScreen())),
                    ),
                    const SizedBox(height: AppTheme.s2),
                    Text(
                        'In demo mode this works on the phone. With the shared backend, farms are approved as suppliers first so only real helpers can answer requests.',
                        style: AppTheme.caption),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Row(children: [
        Expanded(child: Text(label, style: AppTheme.body)),
        IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline_rounded)),
        SizedBox(width: 72, child: Text(value, textAlign: TextAlign.center, style: AppTheme.headline)),
        IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline_rounded)),
      ]);
}

class _Request extends ConsumerWidget {
  final WaterIncident incident;
  final WaterZone? zone;
  final String farm;
  const _Request(this.incident, this.zone, this.farm);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = incident;
    final canOffer = i.stage == IncidentStage.requested || i.stage == IncidentStage.acknowledged;
    final sup = ref.watch(supplierProvider).supplier;
    final mine = ref.watch(supplierProvider).offers.any((o) => o.incidentId == i.id);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(zone?.name ?? 'A community', style: AppTheme.headline)),
          Pill(i.stage.label, color: i.stage == IncidentStage.dispatched ? AppTheme.sprout : AppTheme.warn),
        ]),
        Text(
            '${zone == null ? '' : '${zone!.level.round()}% in the reservoir  •  '}${i.votes} of ${i.threshold} votes${zone == null ? '' : '  •  ${zone!.provider}'}',
            style: AppTheme.footnote),
        if (i.stage == IncidentStage.dispatched)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s1),
            child: Text('${i.trucks} truck${i.trucks == 1 ? '' : 's'}, about ${i.etaMinutes} min. ${i.note}', style: AppTheme.footnote),
          ),
        const SizedBox(height: AppTheme.s3),
        if (mine && i.stage == IncidentStage.dispatched)
          GlassButton(
            label: 'Mark delivered',
            icon: Icons.check_rounded,
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await ref.read(waterProvider.notifier).resolve(i.id);
            },
          )
        else if (canOffer)
          GlassButton(
            label: 'Offer help',
            icon: Icons.local_shipping_rounded,
            accent: _blue,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _OfferSheet(i, zone?.name ?? 'the community', farm, sup),
            ),
          )
        else
          Text(
              i.stage == IncidentStage.open ? 'Still collecting votes. You can offer once it is sent on.' : 'Help is already on the way.',
              style: AppTheme.caption),
      ]),
    );
  }
}

class _OfferSheet extends ConsumerStatefulWidget {
  final WaterIncident incident;
  final String zoneName;
  final String farm;
  final WaterSupplier supplier;
  const _OfferSheet(this.incident, this.zoneName, this.farm, this.supplier);

  @override
  ConsumerState<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends ConsumerState<_OfferSheet> {
  late int _litres = widget.supplier.litresPerDay.clamp(500, 20000);
  int _eta = 90;
  String? _error;

  Future<void> _send() async {
    final s = widget.supplier;
    final trucks = (_litres / 10000).ceil().clamp(1, 10);
    try {
      await ref.read(waterProvider.notifier).dispatch(
            widget.incident.id,
            trucks: trucks,
            etaMinutes: _eta,
            note: '${widget.farm} is bringing ${groupDigits(_litres)} L from a ${s.source.toLowerCase()}, ${s.priceLabel}.',
          );
      ref.read(supplierProvider.notifier).recordOffer(WaterOffer(widget.incident.id, widget.zoneName, _litres, _eta, DateTime.now()));
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not send the offer. Only approved suppliers can answer requests on the shared network.');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Row(children: [
          Expanded(child: Text(label, style: AppTheme.body)),
          IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline_rounded)),
          SizedBox(width: 72, child: Text(value, textAlign: TextAlign.center, style: AppTheme.headline)),
          IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]);
    return SheetFrame(
      title: 'Help ${widget.zoneName}',
      subtitle: 'The community sees who is coming and when.',
      children: [
        stepper('Litres you bring', groupDigits(_litres), () => setState(() => _litres = (_litres - 1000).clamp(500, 100000)),
            () => setState(() => _litres = (_litres + 1000).clamp(500, 100000))),
        stepper('Minutes until you arrive', '$_eta', () => setState(() => _eta = (_eta - 15).clamp(15, 600)),
            () => setState(() => _eta = (_eta + 15).clamp(15, 600))),
        if (_error != null) Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger)),
        const SizedBox(height: AppTheme.s3),
        GlassButton(label: 'Send my offer', icon: Icons.send_rounded, accent: _blue, onPressed: _send),
      ],
    );
  }
}
