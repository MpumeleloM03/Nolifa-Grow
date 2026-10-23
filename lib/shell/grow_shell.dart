import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show GlassTabBar, LowWaterPromptHost, OrderStatus, marketProvider;
import '../store/farm_water_section.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'alerts_tab.dart';
import 'welcome_back.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'settings_tab.dart';

/// Nolifa Grow after sign-in: four tabs. Scanning is first because this is a
/// crop and cattle health app before it is a shop.
class GrowShell extends ConsumerStatefulWidget {
  final int initialTab;
  const GrowShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<GrowShell> createState() => _GrowShellState();
}

class _GrowShellState extends ConsumerState<GrowShell> {
  late int _i = widget.initialTab;

  static const _tabs = [
    ('🔬', Icons.document_scanner_rounded, 'Home'),
    ('📦', Icons.inventory_2_rounded, 'Orders'),
    ('🚨', Icons.notifications_active_rounded, 'Alerts'),
    ('⚙️', Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final toSend = ref.watch(marketProvider.select(
        (s) => s.farmOrders.where((o) => o.status == OrderStatus.newOrder).length));
    final pages = <Widget>[
      const HomeTab(),
      const OrdersTab(),
      const AlertsTab(),
      const SettingsTab(),
    ];
    return WelcomeBackHost(
      child: LowWaterPromptHost(
      waterSections: const [FarmWaterSection()],
      child: Scaffold(
      extendBody: true,
      body: AppBackdrop(
        tint: _i == 1 ? AppTheme.sprout : (_i == 2 ? AppTheme.danger : AppTheme.plantAccent),
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
          ),
        ),
      ),
      bottomNavigationBar: GlassTabBar(
        index: _i,
        tabs: _tabs,
        badges: {if (toSend > 0) 1: toSend},
        onTap: (n) {
          HapticFeedback.selectionClick();
          setState(() => _i = n);
        },
      ),
    )));
  }
}
