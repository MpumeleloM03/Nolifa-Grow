import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show friendlyError;
import '../models/cattle.dart';
import '../models/health_event.dart';
import '../services/cattle_service.dart';
import '../services/health_log_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'care_models.dart';
import 'care_store.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
/// Water and feed reminders for the herd, today's ticks, and the vaccination
/// record for every animal.
class CareScreen extends ConsumerStatefulWidget {
  const CareScreen({super.key});

  @override
  ConsumerState<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends ConsumerState<CareScreen> {
  late final TextEditingController _feed = TextEditingController(text: ref.read(careProvider).settings.feedNotes);

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  void _say(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _addTime(String kind) async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 0));
    if (t == null) return;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final s = ref.read(careProvider).settings;
    final list = [...(kind == 'water' ? s.waterTimes : s.feedTimes)];
    if (list.contains(hm)) return;
    list.add(hm);
    list.sort();
    await ref.read(careProvider.notifier).update(kind == 'water' ? s.copyWith(waterTimes: list) : s.copyWith(feedTimes: list));
  }

  Future<void> _removeTime(String kind, String hm) async {
    final s = ref.read(careProvider).settings;
    final list = [...(kind == 'water' ? s.waterTimes : s.feedTimes)]..remove(hm);
    await ref.read(careProvider.notifier).update(kind == 'water' ? s.copyWith(waterTimes: list) : s.copyWith(feedTimes: list));
  }

  Future<void> _vaccinate(Cattle c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VaccineSheet(animal: c),
    );
    if (saved == true && mounted) _say('Saved to ${c.label}\'s record.');
  }

  @override
  Widget build(BuildContext context) {
    final care = ref.watch(careProvider);
    final store = ref.read(careProvider.notifier);
    final herd = ref.watch(herdProvider);
    final events = ref.watch(healthLogProvider);
    final sum = ref.watch(vaccineSummaryProvider);
    final s = care.settings;
    final now = DateTime.now();

    Widget slots(String kind, String title, String emoji, List<String> times) => GlassCard(
          padding: const EdgeInsets.all(AppTheme.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: AppTheme.s3),
              Expanded(child: Text(title, style: AppTheme.headline)),
              TextButton.icon(
                onPressed: () => _addTime(kind),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add time'),
              ),
            ]),
            if (times.isEmpty) Text('No times set. Add one so the phone can remind you.', style: AppTheme.footnote),
            for (final t in times)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.s2),
                child: Row(children: [
                  Text(t, style: AppTheme.title3),
                  const SizedBox(width: AppTheme.s3),
                  if (store.done(kind, t))
                    Chip(
                      avatar: Icon(Icons.check_circle_rounded, color: AppTheme.ok, size: 18),
                      label: const Text('Done today'),
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    GhostButton(
                      label: 'Done',
                      icon: Icons.check_rounded,
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        store.tick(kind, t);
                      },
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('Remove this time'),
                    icon: Icon(Icons.close_rounded, color: AppTheme.textTertiary),
                    onPressed: () => _removeTime(kind, t),
                  ),
                ]),
              ),
          ]),
        );

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: const Text('Herd care'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: [
                Text('Water, feed and vaccines', style: AppTheme.title2),
                const SizedBox(height: AppTheme.s1),
                Text('Your phone reminds you at these times. What you tick off builds your farm record, which vets and buyers can trust.',
                    style: AppTheme.callout),
                const SizedBox(height: AppTheme.s4),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s2),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.remindersOn,
                    onChanged: (v) => store.update(s.copyWith(remindersOn: v)),
                    title: Text('Phone reminders', style: AppTheme.headline),
                    subtitle: Text('A notification at each time below, every day.', style: AppTheme.footnote),
                  ),
                ),
                const SizedBox(height: AppTheme.s3),
                slots('water', 'Water the herd', '💧', s.waterTimes),
                const SizedBox(height: AppTheme.s3),
                slots('feed', 'Feed the herd', '🌾', s.feedTimes),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  padding: const EdgeInsets.all(AppTheme.s4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('What do you feed?', style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s1),
                    Text('Lick, hay, silage, pasture, feed brand and amounts. Our vets read this to understand how your animals are kept.',
                        style: AppTheme.footnote),
                    const SizedBox(height: AppTheme.s2),
                    TextField(
                      controller: _feed,
                      maxLines: 4,
                      maxLength: 600,
                      style: AppTheme.callout.copyWith(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: tr('For example: veld grazing, 2 kg maize lick per cow a day, hay in winter'),
                        hintStyle: AppTheme.caption,
                        filled: true,
                        fillColor: AppTheme.glassFill,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
                      ),
                      onChanged: (v) => store.update(s.copyWith(feedNotes: v.trim())),
                    ),
                  ]),
                ),
                const SizedBox(height: AppTheme.s6),
                Text('Vaccinations', style: AppTheme.title2),
                const SizedBox(height: AppTheme.s1),
                if (sum != null)
                  Text(
                      sum.total == 0
                          ? 'Add animals to your herd to keep their vaccine record.'
                          : '${sum.current} of ${sum.total} vaccinated and up to date. ${sum.needAttention == 0 ? 'Nothing needs a record.' : '${sum.needAttention} still need an answer or a booster.'}',
                      style: AppTheme.callout),
                const SizedBox(height: AppTheme.s3),
                herd.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(friendlyError(e, doing: 'load your herd'), style: AppTheme.callout),
                  data: (list) {
                    final active = [for (final c in list) if (c.status == CattleStatus.active) c];
                    return Column(children: [
                      for (final c in active)
                        _AnimalVaccineRow(
                          animal: c,
                          status: vaccineStatusOf([for (final e in events) if (e.animalId == c.id) e], now),
                          onTap: () => _vaccinate(c),
                        ),
                    ]);
                  },
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AnimalVaccineRow extends StatelessWidget {
  final Cattle animal;
  final VaccineStatus status;
  final VoidCallback onTap;
  const _AnimalVaccineRow({required this.animal, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.standing) {
      VaccineStanding.current => ('Up to date', AppTheme.ok),
      VaccineStanding.due => ('Booster due', AppTheme.warn),
      VaccineStanding.declined => ('Not vaccinated', AppTheme.danger),
      VaccineStanding.unknown => ('Not answered', AppTheme.textTertiary),
    };
    final last = status.last;
    final detail = last == null
        ? 'Has ${animal.label} been vaccinated?'
        : status.standing == VaccineStanding.declined
            ? 'You said no on ${_d(last.at)}'
            : '${last.condition ?? 'Vaccine'}, ${_d(last.at)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s2),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
        onTap: onTap,
        child: Row(children: [
          Text(animal.species.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${animal.label}  ·  ${animal.tagNumber}', style: AppTheme.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(detail, style: AppTheme.footnote),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: AppTheme.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  static String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _VaccineSheet extends ConsumerStatefulWidget {
  final Cattle animal;
  const _VaccineSheet({required this.animal});

  @override
  ConsumerState<_VaccineSheet> createState() => _VaccineSheetState();
}

class _VaccineSheetState extends ConsumerState<_VaccineSheet> {
  bool? _yes;
  String? _vaccine;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 4)),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_yes == null) return;
    if (_yes == true && _vaccine == null) {
      setState(() => _error = 'Pick which vaccine it was.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthLogProvider.notifier).record(
            widget.animal.id,
            _yes == true ? HealthKind.vaccination : HealthKind.notVaccinated,
            condition: _yes == true ? _vaccine : null,
            at: _yes == true ? _date : DateTime.now(),
            note: _yes == true ? 'Vaccinated: $_vaccine' : 'Farmer reports no vaccination',
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, doing: 'save that');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaccines = vaccinesFor(widget.animal.species);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.sheet, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
        padding: const EdgeInsets.all(AppTheme.s6),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Has ${widget.animal.label} been vaccinated?', style: AppTheme.title3),
              const SizedBox(height: AppTheme.s3),
              Row(children: [
                Expanded(child: _Choice('Yes', _yes == true, () => setState(() => _yes = true))),
                const SizedBox(width: AppTheme.s2),
                Expanded(child: _Choice('No', _yes == false, () => setState(() => _yes = false))),
              ]),
              if (_yes == true) ...[
                const SizedBox(height: AppTheme.s4),
                Text('Which vaccine?', style: AppTheme.headline),
                const SizedBox(height: AppTheme.s2),
                Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                  for (final v in vaccines) _Choice(v, _vaccine == v, () => setState(() => _vaccine = v)),
                ]),
                const SizedBox(height: AppTheme.s3),
                GhostButton(label: 'Given on ${_date.day}/${_date.month}/${_date.year}', icon: Icons.event_rounded, onPressed: _pickDate),
              ],
              if (_yes == false) ...[
                const SizedBox(height: AppTheme.s3),
                Text('We keep this honest record. A vet can then advise which vaccines your herd needs in your area.', style: AppTheme.footnote),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppTheme.s2),
                Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
              ],
              const SizedBox(height: AppTheme.s4),
              GlassButton(label: _busy ? 'Saving' : 'Save', icon: Icons.check_rounded, onPressed: (_yes == null || _busy) ? null : _save),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice(this.label, this.on, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppTheme.sprout.withValues(alpha: 0.22) : AppTheme.glassFill,
            borderRadius: BorderRadius.circular(AppTheme.rChip),
            border: Border.all(color: on ? AppTheme.sprout : AppTheme.glassBorder),
          ),
          child: Text(label, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
}
