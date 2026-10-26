import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        DriverTrackingHost,
        GlassTabBar,
        LowWaterPromptHost,
        OrderStatus,
        RoadAlertsScreen,
        ShopHomePage,
        WaterPage,
        marketProvider,
        openDropMenu;
import '../driver/driver_home.dart';
import '../driver/earnings_tab.dart';
import '../members/members_service.dart' show applicationProvider;
import '../services/auth_service.dart';
import '../services/notices.dart';
import '../store/farm_water_section.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'alerts_tab.dart';
import 'welcome_back.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'settings_tab.dart';

/// Nolifa after sign-in. One app, three people, each sent to what they use:
///
/// * Community member: Diagnose, Outbreaks, Water, Shop, Me.
/// * Farmer: Diagnose, Outbreaks, Water, Sell, Me.
/// * Driver: Jobs, Roads, Earnings, Me.
///
/// Diagnosis, the live outbreak map and water each have their own tab, so
/// everyone nearby is protected, not only farmers. A community member never
/// sees selling or driver tools; a driver never sees the farm or the shop.
class GrowShell extends ConsumerStatefulWidget {
  final int initialTab;
  const GrowShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<GrowShell> createState() => _GrowShellState();
}

typedef _Tab = (String, IconData, String);

class _GrowShellState extends ConsumerState<GrowShell> {
  late int _i = widget.initialTab;

  static const _Tab _diagnose = ('', Icons.health_and_safety_rounded, 'Diagnose');
  static const _Tab _outbreaks = ('', Icons.map_rounded, 'Outbreaks');
  static const _Tab _water = ('', Icons.water_drop_rounded, 'Water');
  static const _Tab _shop = ('', Icons.storefront_rounded, 'Shop');
  static const _Tab _sell = ('', Icons.inventory_2_rounded, 'Sell');
  static const _Tab _jobs = ('', Icons.delivery_dining_rounded, 'Jobs');
  static const _Tab _roads = ('', Icons.traffic_rounded, 'Roads');
  static const _Tab _earnings = ('', Icons.payments_rounded, 'Earnings');
  static const _Tab _me = ('', Icons.person_rounded, 'Me');

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    // The name a farm gave Nolifa is the name buyers see. Once staff approve the
    // application, it becomes the store name if the farmer has not typed another.
    ref.listen<AsyncValue<Map<String, dynamic>?>>(applicationProvider, (_, a) {
      final app = a.valueOrNull;
      final name = '${(app?['data'] as Map?)?['farmName'] ?? ''}'.trim();
      final profile = ref.read(marketProvider).profile;
      if (app?['status'] == 'approved' && name.isNotEmpty && profile.farmName.trim().isEmpty) {
        ref.read(marketProvider.notifier).updateProfile(profile.copyWith(farmName: name));
      }
    });
    final community = user?.isCommunity ?? false;
    final driver = user?.isDriver ?? false;

    final List<_Tab> tabs;
    final List<Widget> pages;
    final Map<int, int> badges;
    if (driver) {
      final open = ref.watch(marketProvider.select((s) => s.openJobs.length));
      tabs = const [_jobs, _roads, _earnings, _me];
      pages = const [DriverHome(), RoadAlertsScreen(), EarningsTab(), SettingsTab()];
      badges = {if (open > 0) 0: open};
    } else if (community) {
      // Free plant and animal checks and the outbreak map protect everyone nearby.
      tabs = const [_diagnose, _outbreaks, _water, _shop, _me];
      pages = [
        const HomeTab(),
        const AlertsTab(),
        const WaterPage(),
        ShopHomePage(onMenu: () => openDropMenu(context)),
        const SettingsTab(),
      ];
      badges = const {};
    } else {
      final toSend = ref.watch(marketProvider.select(
          (s) => s.farmOrders.where((o) => o.status == OrderStatus.newOrder && o.paid).length));
      tabs = const [_diagnose, _outbreaks, _water, _sell, _me];
      pages = const [
        HomeTab(),
        AlertsTab(),
        WaterPage(extraSections: [FarmWaterSection()]),
        OrdersTab(),
        SettingsTab(),
      ];
      badges = {if (toSend > 0) 3: toSend};
    }

    final i = _i.clamp(0, pages.length - 1);
    final tint = switch (tabs[i].$3) {
      'Outbreaks' => AppTheme.danger,
      'Water' => const Color(0xFF5AB8F0),
      'Sell' || 'Shop' || 'Earnings' => AppTheme.sprout,
      'Jobs' || 'Roads' => AppTheme.livestockAccent,
      _ => AppTheme.plantAccent,
    };

    final unread = ref.watch(unreadNoticesProvider);
    final shownBadges = {...badges, if (unread > 0) tabs.length - 1: unread};

    final scaffold = Scaffold(
      extendBody: true,
      body: AppBackdrop(
        tint: tint,
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: KeyedSubtree(key: ValueKey('${user?.farmType}-$i'), child: pages[i]),
          ),
        ),
      ),
      bottomNavigationBar: GlassTabBar(
        index: i,
        tabs: tabs,
        badges: shownBadges,
        onTap: (n) {
          HapticFeedback.selectionClick();
          setState(() => _i = n);
        },
      ),
    );

    // Drivers get no farm or water pop-ups: their app is the road.
    if (driver) return NoticesHost(child: DriverTrackingHost(child: scaffold));
    return NoticesHost(
      child: WelcomeBackHost(
        child: LowWaterPromptHost(
          waterSections: community ? const [] : const [FarmWaterSection()],
          child: scaffold,
        ),
      ),
    );
  }
}
