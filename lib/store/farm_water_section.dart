import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        Pill,
        WaterPrefs,
        litresPerCattlePerDay,
        marketUidProvider,
        waterProvider,
        waterRepositoryProvider;
import '../models/cattle.dart';
import '../services/cattle_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'store_common.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Litres the herd drinks in a day, at the planner's per-head figure.
int herdLitresPerDay(int head) => head * litresPerCattlePerDay;

/// Days a tank lasts for the herd alone. Null when there is no herd to supply.
double? herdTankDays({required int head, required int tankLitres}) =>
    head <= 0 ? null : tankLitres / herdLitresPerDay(head);

/// "Your herd" block for the farmer's water radar. It reads the head count from
/// the herd register and hands it to the water planner, so the planner counts
/// animals as well as people.
class FarmWaterSection extends ConsumerStatefulWidget {
  const FarmWaterSection({super.key});

  @override
  ConsumerState<FarmWaterSection> createState() => _FarmWaterSectionState();
}

/// Animals still on the farm, from the herd register, counted in cow-sized
/// drinkers (ten goats drink about as much as one and a half cows). Zero while
/// it loads.
int _activeHead(AsyncValue<List<Cattle>> register) {
  final active = register.valueOrNull?.where((c) => c.status == CattleStatus.active) ?? const <Cattle>[];
  return active.fold<double>(0, (sum, c) => sum + c.species.waterWeight).round();
}

class _FarmWaterSectionState extends ConsumerState<FarmWaterSection> {
  /// True once the planner holds the farmer's saved details. Saving the herd
  /// before that would overwrite their household, tank and community with
  /// defaults.
  bool _plannerReady = false;
  WaterPrefs? _saved;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
        herdProvider.select(_activeHead), (_, head) => _syncPlanner(head),
        fireImmediately: true);
    // The planner loads saved details in the background and can overwrite the
    // count, so the register is re-applied whenever they change.
    ref.listenManual(waterProvider.select((s) => s.prefs), (_, __) {
      final saved = _saved;
      if (saved != null && !_plannerReady && _matchesSaved(saved)) {
        _plannerReady = true;
      }
      _syncPlanner(_activeHead(ref.read(herdProvider)));
    });
    _awaitSavedPrefs();
  }

  /// Reads the same saved details the planner is loading, so the section knows
  /// when the planner has caught up.
  Future<void> _awaitSavedPrefs() async {
    WaterPrefs? saved;
    try {
      saved = await ref
          .read(waterRepositoryProvider)
          .loadPrefs(ref.read(marketUidProvider));
    } catch (_) {
      // Offline: the planner has nothing saved to lose.
    }
    if (!mounted) return;
    _saved = saved;
    if (saved == null || _matchesSaved(saved)) {
      _plannerReady = true;
      _syncPlanner(_activeHead(ref.read(herdProvider)));
    }
  }

  bool _matchesSaved(WaterPrefs saved) {
    final now = ref.read(waterProvider).prefs;
    return now.zoneId == saved.zoneId &&
        now.household == saved.household &&
        now.tankLitres == saved.tankLitres &&
        now.herd == saved.herd;
  }

  /// The register is the truth when it has animals in it. Deferred a tick
  /// because this can fire while the page is still building.
  void _syncPlanner(int registered) {
    if (registered == 0 || !_plannerReady) return;
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(waterProvider).prefs.herd != registered) {
        ref.read(waterProvider.notifier).setHerd(registered);
      }
    });
  }

  void _step(int by) {
    HapticFeedback.selectionClick();
    final now = ref.read(waterProvider).prefs.herd;
    ref.read(waterProvider.notifier).setHerd(now + by);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(waterProvider.select((s) => s.prefs));
    final registered = ref.watch(herdProvider.select(_activeHead));
    final fromRegister = registered > 0;
    final head = fromRegister ? registered : prefs.herd;
    final need = herdLitresPerDay(head);
    final days = herdTankDays(head: head, tankLitres: prefs.tankLitres);
    final daysColor = days == null
        ? AppTheme.textSecondary
        : days < 2
            ? AppTheme.danger
            : days < 5
                ? AppTheme.warn
                : AppTheme.sprout;

    return GlassCard(
      tint: waterBlue.withValues(alpha: 0.10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Glyph('🐄', size: 22),
          const SizedBox(width: AppTheme.s2),
          Expanded(child: Text('Your herd', style: AppTheme.title3)),
          Pill('${groupDigits(head)} head',
              color: waterBlue, icon: Icons.pets_rounded),
        ]),
        const SizedBox(height: AppTheme.s3),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: need.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(groupDigits(v),
                    style: AppTheme.largeTitle.copyWith(color: waterBlue)),
              ),
              const SizedBox(width: AppTheme.s2),
              Text('L a day', style: AppTheme.callout),
            ]),
        const SizedBox(height: AppTheme.s1),
        Text(
          head == 0
              ? 'No animals counted yet. Set your head count to see what they drink.'
              : 'Your herd needs about ${groupDigits(need)} litres a day, at $litresPerCattlePerDay litres a head.',
          style: AppTheme.footnote,
        ),
        const SizedBox(height: AppTheme.s4),
        Row(children: [
          const Icon(Icons.water_rounded, size: 18, color: waterBlue),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: Text(
              prefs.tankLitres > 0
                  ? 'Tank on site: ${groupDigits(prefs.tankLitres)} L'
                  : 'No tank saved yet. Add its size in your water plan.',
              style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary),
            ),
          ),
          if (days != null && prefs.tankLitres > 0)
            Pill('${days.toStringAsFixed(1)} days for the herd',
                color: daysColor),
        ]),
        const SizedBox(height: AppTheme.s3),
        if (fromRegister)
          Text('Counted from your herd register. Goats and sheep count as a fraction of a cow, because they drink less.',
              style: AppTheme.caption)
        else ...[
          Text('Not in your herd register? Set the head count by hand.',
              style: AppTheme.caption),
          const SizedBox(height: AppTheme.s2),
          Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
            for (final by in const [-10, -1, 1, 10])
              ChoiceChipButton(
                label: by > 0 ? '+$by' : '$by',
                onTap: () => _step(by),
              ),
          ]),
        ],
      ]),
    );
  }
}
