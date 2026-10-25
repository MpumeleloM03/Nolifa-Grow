import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cattle.dart';
import '../../models/health_event.dart';
import '../../models/species.dart';
import '../../services/health_log_service.dart';
import '../../theme/app_theme.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
Color healthColor(HealthState s) => switch (s) {
      HealthState.sick => AppTheme.danger,
      HealthState.watch => AppTheme.warn,
      HealthState.well => AppTheme.ok,
      HealthState.unknown => AppTheme.textTertiary,
    };

/// Each animal's current state, worked out from its health record.
final animalHealthProvider = Provider<Map<String, HealthState>>((ref) {
  final events = ref.watch(healthLogProvider);
  final byAnimal = <String, List<HealthEvent>>{};
  for (final e in events) {
    byAnimal.putIfAbsent(e.animalId, () => []).add(e);
  }
  final now = DateTime.now();
  return {for (final e in byAnimal.entries) e.key: healthStateOf(e.value, now)};
});

HealthState stateOf(Map<String, HealthState> all, Cattle a) => all[a.id] ?? HealthState.unknown;

/// A row of species buttons with how many of each the farmer has. [selected]
/// null means all of them.
class SpeciesChips extends StatelessWidget {
  final List<Cattle> herd;
  final Species? selected;
  final ValueChanged<Species?> onChanged;
  final bool includeAll;
  const SpeciesChips({
    super.key,
    required this.herd,
    required this.selected,
    required this.onChanged,
    this.includeAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = herd.where((a) => a.status == CattleStatus.active).toList();
    Widget chip(String label, bool on, VoidCallback tap) => Padding(
          padding: const EdgeInsets.only(right: AppTheme.s2),
          child: GestureDetector(
            onTap: tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s2),
              decoration: BoxDecoration(
                color: on ? AppTheme.livestockAccent.withValues(alpha: 0.2) : AppTheme.glassFill,
                borderRadius: BorderRadius.circular(AppTheme.rChip),
                border: Border.all(color: on ? AppTheme.livestockAccent : AppTheme.glassBorderSoft),
              ),
              child: Text(label,
                  style: AppTheme.footnote.copyWith(
                    color: on ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (includeAll) chip('All ${active.length}', selected == null, () => onChanged(null)),
        for (final s in Species.values)
          chip('${s.plural} ${active.where((a) => a.species == s).length}', selected == s, () => onChanged(s)),
      ]),
    );
  }
}

/// A small coloured dot showing how an animal is doing.
class HealthDot extends StatelessWidget {
  final HealthState state;
  const HealthDot(this.state, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: healthColor(state), shape: BoxShape.circle),
      );
}

String ageText(Cattle a) {
  final m = a.ageMonths;
  if (m == null) return '';
  return m >= 24 ? '${(m / 12).floor()} yrs' : '$m mo';
}
