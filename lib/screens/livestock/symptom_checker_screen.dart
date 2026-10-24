import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cattle.dart';
import '../../models/health_event.dart';
import '../../models/livestock_disease.dart';
import '../../models/species.dart';
import '../../services/health_log_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Tick what you see and get guidance. Open it for one animal and the result
/// can be saved into that animal's health record; open it without one and it
/// asks which kind of animal first.
class SymptomCheckerScreen extends ConsumerStatefulWidget {
  final Species? species;
  final Cattle? animal;
  const SymptomCheckerScreen({super.key, this.species, this.animal});

  @override
  ConsumerState<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends ConsumerState<SymptomCheckerScreen> {
  final Set<String> _selected = {};
  late Species? _species = widget.animal?.species ?? widget.species;
  bool _saved = false;

  Future<void> _save(ConditionMatch top) async {
    final a = widget.animal!;
    await ref.read(healthLogProvider.notifier).record(
          a.id,
          HealthKind.check,
          symptomIds: _selected.toList(),
          condition: top.condition.name,
          urgency: top.condition.urgency,
        );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Symptom>>{};
    if (_species != null) {
      for (final s in LivestockDatabase.symptomsFor(_species!)) {
        grouped.putIfAbsent(s.group, () => []).add(s);
      }
    }
    final matches = LivestockDatabase.match(_selected, species: _species);

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Check symptoms'),
                actions: [
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: Text('Clear',
                          style: AppTheme.subhead
                              .copyWith(color: AppTheme.livestockAccent)),
                    ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(
                  children: [
                    Text(
                        widget.animal == null
                            ? 'What do you see?'
                            : 'What do you see on ${widget.animal!.label}?',
                        style: AppTheme.title1),
                    const SizedBox(height: AppTheme.s2),
                    Text(
                      'Tick everything that applies. The more you tick, the better the guidance.',
                      style: AppTheme.callout,
                    ),
                    if (widget.animal == null) ...[
                      const SizedBox(height: AppTheme.s4),
                      Text('WHICH ANIMAL?',
                          style: AppTheme.caption.copyWith(letterSpacing: 1.1, color: AppTheme.textTertiary)),
                      const SizedBox(height: AppTheme.s3),
                      Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                        for (final sp in Species.values)
                          GestureDetector(
                            onTap: () => setState(() {
                              _species = sp;
                              _selected.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                              decoration: BoxDecoration(
                                color: _species == sp
                                    ? AppTheme.livestockAccent.withValues(alpha: 0.2)
                                    : AppTheme.glassFill,
                                borderRadius: BorderRadius.circular(AppTheme.rChip),
                                border: Border.all(
                                    color: _species == sp ? AppTheme.livestockAccent : AppTheme.glassBorderSoft,
                                    width: _species == sp ? 1.5 : 1),
                              ),
                              child: Text('${sp.emoji} ${sp.singular}',
                                  style: AppTheme.footnote.copyWith(
                                      color: _species == sp ? AppTheme.textPrimary : AppTheme.textSecondary)),
                            ),
                          ),
                      ]),
                    ],
                    if (_species == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTheme.s6),
                        child: Text('Pick the kind of animal and the signs to look for will appear.',
                            style: AppTheme.callout),
                      ),
                    const SizedBox(height: AppTheme.s6),
                    ...grouped.entries.map((g) => Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.key.toUpperCase(),
                                  style: AppTheme.caption.copyWith(
                                      letterSpacing: 1.1,
                                      color: AppTheme.textTertiary)),
                              const SizedBox(height: AppTheme.s3),
                              Wrap(
                                spacing: AppTheme.s2,
                                runSpacing: AppTheme.s2,
                                children: g.value
                                    .map((s) => _SymptomChip(
                                          symptom: s,
                                          selected: _selected.contains(s.id),
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _saved = false;
                                              _selected.contains(s.id)
                                                  ? _selected.remove(s.id)
                                                  : _selected.add(s.id);
                                            });
                                          },
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        )),
                    if (matches.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.s4),
                      const Divider(),
                      const SizedBox(height: AppTheme.s5),
                      Text('What this could be', style: AppTheme.title2),
                      const SizedBox(height: AppTheme.s2),
                      Text(
                        'Ranked by how well your symptoms fit. This is guidance, not a diagnosis.',
                        style: AppTheme.footnote,
                      ),
                      const SizedBox(height: AppTheme.s4),
                      ...matches.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s3),
                            child: _MatchCard(match: m),
                          )),
                      if (widget.animal != null) ...[
                        const SizedBox(height: AppTheme.s2),
                        GlassButton(
                          label: _saved ? 'Saved to the health record' : 'Save to ${widget.animal!.label}\'s record',
                          icon: _saved ? Icons.check_circle_rounded : Icons.bookmark_add_rounded,
                          accent: AppTheme.livestockAccent,
                          onPressed: _saved ? null : () => _save(matches.first),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  final Symptom symptom;
  final bool selected;
  final VoidCallback onTap;

  const _SymptomChip(
      {required this.symptom, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4, vertical: AppTheme.s3),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.livestockAccent.withValues(alpha: 0.2)
              : AppTheme.glassFill,
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(
            color: selected
                ? AppTheme.livestockAccent
                : AppTheme.glassBorderSoft,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded,
                  size: 15, color: AppTheme.livestockAccent),
              const SizedBox(width: AppTheme.s2),
            ],
            Text(
              symptom.label,
              style: AppTheme.footnote.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final ConditionMatch match;
  const _MatchCard({required this.match});

  Color get _urgencyColor => switch (match.condition.urgency) {
        Urgency.notifiable => AppTheme.danger,
        Urgency.emergency => AppTheme.danger,
        Urgency.soon => AppTheme.warn,
        Urgency.monitor => AppTheme.ok,
      };

  @override
  Widget build(BuildContext context) {
    final c = match.condition;
    final notifiable = c.urgency == Urgency.notifiable;

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s5),
      tint: notifiable ? AppTheme.danger.withValues(alpha: 0.12) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.plainName, style: AppTheme.title3)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.s2, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.glassFill,
                  borderRadius: BorderRadius.circular(AppTheme.s2),
                ),
                child: Text('${(match.score * 100).round()}% fit',
                    style: AppTheme.caption),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s3),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.s3, vertical: AppTheme.s2),
            decoration: BoxDecoration(
              color: _urgencyColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              border: Border.all(color: _urgencyColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(
                  notifiable
                      ? Icons.gavel_rounded
                      : Icons.warning_amber_rounded,
                  size: 16,
                  color: _urgencyColor,
                ),
                const SizedBox(width: AppTheme.s2),
                Expanded(
                  child: Text(c.urgency.label,
                      style: AppTheme.footnote.copyWith(
                          color: _urgencyColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.s3),
          Text(c.urgency.guidance, style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s3),
          Text(c.whatItIs, style: AppTheme.subhead),
          const SizedBox(height: AppTheme.s4),
          Text('WHAT TO DO',
              style: AppTheme.caption
                  .copyWith(letterSpacing: 1.1, color: AppTheme.textTertiary)),
          const SizedBox(height: AppTheme.s3),
          ...c.actions.indexed.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _urgencyColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${e.$1 + 1}',
                          style:
                              AppTheme.caption.copyWith(color: _urgencyColor)),
                    ),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(child: Text(e.$2, style: AppTheme.subhead)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
