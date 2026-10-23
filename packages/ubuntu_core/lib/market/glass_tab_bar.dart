import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The floating glass bottom bar every Nolifa app uses. Each tab is an icon and
/// a label; [badges] puts a small count on a tab (for example new orders).
class GlassTabBar extends StatelessWidget {
  final int index;
  final List<(String, IconData, String)> tabs; // emoji, icon, label
  final ValueChanged<int> onTap;
  final Map<int, int> badges;

  const GlassTabBar({
    super.key,
    required this.index,
    required this.tabs,
    required this.onTap,
    this.badges = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppTheme.s4, 0, AppTheme.s4, MediaQuery.of(context).padding.bottom + 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: index == i
                            ? AppTheme.sprout.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Stack(clipBehavior: Clip.none, children: [
                          AnimatedScale(
                            scale: index == i ? 1.18 : 1,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            child: Icon(tabs[i].$2,
                                size: 22,
                                color: index == i ? AppTheme.sprout : AppTheme.textSecondary),
                          ),
                          if ((badges[i] ?? 0) > 0)
                            Positioned(
                              right: -10,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text('${badges[i]}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        Text(tabs[i].$3,
                            style: AppTheme.caption.copyWith(
                                color: index == i ? AppTheme.sprout : AppTheme.textSecondary)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
