import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../models/cattle.dart';
import '../../models/health_event.dart';
import '../../models/livestock_disease.dart';
import '../../services/auth_service.dart';
import '../../services/cattle_service.dart';
import '../../services/health_log_service.dart';
import '../../services/region_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import 'add_cattle_screen.dart';
import 'herd_widgets.dart';
import 'location_picker_screen.dart';
import 'symptom_checker_screen.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// One animal: how it is doing, its health record and where it is kept.
class AnimalDetailScreen extends ConsumerWidget {
  final String animalId;
  const AnimalDetailScreen({super.key, required this.animalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final herd = ref.watch(herdProvider).valueOrNull ?? const <Cattle>[];
    final matches = herd.where((a) => a.id == animalId);
    if (matches.isEmpty) {
      return Scaffold(
        body: AppBackdrop(
          tint: AppTheme.livestockAccent,
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              ),
              Expanded(child: Center(child: Text('This animal is no longer on the register.', style: AppTheme.callout))),
            ]),
          ),
        ),
      );
    }
    final a = matches.first;
    final events = ref.watch(healthLogProvider.select((all) => [for (final e in all) if (e.animalId == a.id) e]))
      ..sort((x, y) => y.at.compareTo(x.at));
    final state = healthStateOf(events, DateTime.now());

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
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
                title: Text(a.label),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: tr('Edit details'),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => AddCattleScreen(existing: a))),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  _Header(a, state),
                  const SizedBox(height: AppTheme.s4),
                  GlassButton(
                    label: 'Check symptoms',
                    icon: Icons.medical_services_outlined,
                    accent: AppTheme.livestockAccent,
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SymptomCheckerScreen(animal: a))),
                  ),
                  const SizedBox(height: AppTheme.s2),
                  Row(children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Add note',
                        icon: Icons.edit_note_rounded,
                        onPressed: () => _addEntry(context, ref, a),
                      ),
                    ),
                    const SizedBox(width: AppTheme.s2),
                    Expanded(
                      child: GhostButton(
                        label: 'Mark recovered',
                        icon: Icons.favorite_rounded,
                        onPressed: state == HealthState.well || state == HealthState.unknown
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                ref.read(healthLogProvider.notifier).record(a.id, HealthKind.recovered,
                                    note: 'Marked recovered by the farmer');
                              },
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppTheme.s6),
                  Text('Where it is', style: AppTheme.title3),
                  const SizedBox(height: AppTheme.s3),
                  _LocationCard(a),
                  const SizedBox(height: AppTheme.s6),
                  Text('Health record', style: AppTheme.title3),
                  const SizedBox(height: AppTheme.s3),
                  if (events.isEmpty)
                    GlassCard(
                        child: Text('Nothing recorded yet. Check symptoms or add a note when you vaccinate or treat.',
                            style: AppTheme.callout))
                  else
                    for (final e in events)
                      Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: _EventTile(e)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addEntry(BuildContext context, WidgetRef ref, Cattle a) async {
    final text = TextEditingController();
    var kind = HealthKind.note;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(AppTheme.s5, AppTheme.s5, AppTheme.s5, MediaQuery.of(ctx).viewInsets.bottom + AppTheme.s5),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add to ${a.label}\'s record', style: AppTheme.title3),
            const SizedBox(height: AppTheme.s3),
            Wrap(spacing: AppTheme.s2, children: [
              for (final k in const [HealthKind.note, HealthKind.treatment, HealthKind.vaccination])
                ChoiceChip(
                  label: Text(k.label),
                  selected: kind == k,
                  onSelected: (_) => setS(() => kind = k),
                ),
            ]),
            const SizedBox(height: AppTheme.s3),
            TextField(
              controller: text,
              autofocus: true,
              maxLines: 3,
              style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: tr('What was done, which product, which vet'),
                hintStyle: AppTheme.subhead,
                filled: true,
                fillColor: AppTheme.glassFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
              ),
            ),
            const SizedBox(height: AppTheme.s3),
            GlassButton(
              label: 'Save',
              icon: Icons.check_rounded,
              accent: AppTheme.livestockAccent,
              onPressed: () => Navigator.pop(sheet, true),
            ),
          ]),
        ),
      ),
    );
    if (saved == true && text.text.trim().isNotEmpty) {
      await ref.read(healthLogProvider.notifier).record(a.id, kind, note: text.text);
    }
  }
}

class _Header extends StatelessWidget {
  final Cattle a;
  final HealthState state;
  const _Header(this.a, this.state);

  @override
  Widget build(BuildContext context) {
    final details = [
      a.species.singular,
      if (a.breed.isNotEmpty) a.breed,
      a.sex,
      if (ageText(a).isNotEmpty) ageText(a),
    ].join(' · ');
    return GlassCard(
      child: Row(children: [
        Text(a.species.emoji, style: const TextStyle(fontSize: 44)),
        const SizedBox(width: AppTheme.s4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.label, style: AppTheme.title2),
            Text(a.name.isEmpty ? details : 'Tag ${a.tagNumber} · $details', style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s2),
            Row(children: [
              HealthDot(state),
              const SizedBox(width: 6),
              Text(state.label, style: AppTheme.footnote.copyWith(color: healthColor(state))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  final Cattle a;
  const _LocationCard(this.a);

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final region = ref.read(currentUserProvider)?.region ?? '';
    final centre = (RegionService.findByName(region) ?? RegionService.regions.first).center;
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          start: LatLng(centre.latitude, centre.longitude),
          current: a.hasLocation ? LatLng(a.lat!, a.lng!) : null,
          title: 'Where is ${a.label}?',
        ),
      ),
    );
    final uid = ref.read(currentUserProvider)?.uid;
    if (picked == null || uid == null) return;
    await ref.read(cattleServiceProvider).update(
          uid,
          a.copyWith(lat: picked.latitude, lng: picked.longitude, locatedAt: DateTime.now()),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (a.camp.isNotEmpty) Text(a.camp, style: AppTheme.headline),
        if (a.hasLocation) ...[
          if (a.locatedAt != null) Text('Pinned ${_day(a.locatedAt!)}', style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s3),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            child: SizedBox(
              height: 150,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(initialCenter: LatLng(a.lat!, a.lng!), initialZoom: 14),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nolifa.grow'),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(a.lat!, a.lng!),
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.location_on_rounded, size: 40, color: AppTheme.livestockAccent),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ] else if (a.camp.isEmpty)
          Text('No location yet.', style: AppTheme.callout),
        const SizedBox(height: AppTheme.s3),
        GhostButton(
          label: a.hasLocation ? 'Move the pin' : 'Drop a pin on the map',
          icon: Icons.location_on_outlined,
          onPressed: () => _move(context, ref),
        ),
      ]),
    );
  }
}

class _EventTile extends StatelessWidget {
  final HealthEvent e;
  const _EventTile(this.e);

  @override
  Widget build(BuildContext context) {
    final color = switch (e.urgency) {
      Urgency.notifiable || Urgency.emergency => AppTheme.danger,
      Urgency.soon => AppTheme.warn,
      _ => e.kind == HealthKind.recovered ? AppTheme.ok : AppTheme.textTertiary,
    };
    final icon = switch (e.kind) {
      HealthKind.check => Icons.medical_services_outlined,
      HealthKind.treatment => Icons.healing_rounded,
      HealthKind.vaccination => Icons.vaccines_rounded,
      HealthKind.notVaccinated => Icons.do_not_disturb_on_outlined,
      HealthKind.recovered => Icons.favorite_rounded,
      HealthKind.note => Icons.notes_rounded,
    };
    final signs = [
      for (final id in e.symptomIds)
        LivestockDatabase.symptoms.where((s) => s.id == id).map((s) => s.label.toLowerCase()).firstOrNull ?? id
    ];
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      radius: AppTheme.rControl,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.kind == HealthKind.check && e.condition != null ? 'Looked like ${e.condition}' : e.kind.label,
                style: AppTheme.headline),
            Text(_day(e.at), style: AppTheme.caption),
            if (e.urgency != null) Text(e.urgency!.label, style: AppTheme.footnote.copyWith(color: color)),
            if (signs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Signs: ${signs.join(', ')}', style: AppTheme.footnote)),
            if (e.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(e.note, style: AppTheme.subhead)),
          ]),
        ),
      ]),
    );
  }
}
