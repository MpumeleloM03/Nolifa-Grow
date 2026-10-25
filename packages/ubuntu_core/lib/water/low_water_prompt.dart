import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'water_models.dart';
import 'water_screens.dart';
import 'water_store.dart';

import '../tr_text.dart' show Text;
/// Set once the low-water pop-up has been shown in this run of the app, so it
/// greets a person on opening and then leaves them alone.
final lowWaterPromptShownProvider = StateProvider<bool>((ref) => false);

/// Wraps an app's home. When it opens and the person's community is Low or
/// Critical, a pop-up says so and offers to take them to the Water page to add
/// their vote to the community voice.
class LowWaterPromptHost extends ConsumerStatefulWidget {
  final Widget child;

  /// Extra sections for the Water page this opens (Grow adds its herd section).
  final List<Widget> waterSections;
  const LowWaterPromptHost({super.key, required this.child, this.waterSections = const []});

  @override
  ConsumerState<LowWaterPromptHost> createState() => _LowWaterPromptHostState();
}

class _LowWaterPromptHostState extends ConsumerState<LowWaterPromptHost> {
  void _check(WaterState s) {
    final zone = s.myZone;
    if (zone == null || ref.read(lowWaterPromptShownProvider)) return;
    if (!zone.status.canRequestHelp) return;
    ref.read(lowWaterPromptShownProvider.notifier).state = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = s.forecastOf(zone.id);
      final days = f?.daysToCritical;
      HapticFeedback.mediumImpact();
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppTheme.s5),
          child: GlassCard(
            strong: true,
            padding: const EdgeInsets.all(AppTheme.s5),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Glyph('💧', size: 44),
              const SizedBox(height: AppTheme.s2),
              Text('${zone.name} water is ${zone.status.label.toLowerCase()}', style: AppTheme.title2),
              const SizedBox(height: AppTheme.s1),
              Text(
                  '${zone.level.round()}% in the reservoir${days == null ? '' : ', about ${days.toStringAsFixed(1)} days until critical'}. When enough neighbours vote, the provider sends trucks.',
                  style: AppTheme.callout),
              const SizedBox(height: AppTheme.s4),
              GlassButton(
                label: 'Vote for help',
                icon: Icons.how_to_vote_rounded,
                accent: AppTheme.danger,
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => WaterScreen(extraSections: widget.waterSections)));
                },
              ),
              const SizedBox(height: AppTheme.s2),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Not now', style: AppTheme.callout),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<WaterState>(waterProvider, (_, next) => _check(next));
    // The zones may already be loaded by the time this mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check(ref.read(waterProvider));
    });
    return widget.child;
  }
}
