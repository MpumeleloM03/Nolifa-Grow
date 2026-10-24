import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'alert_actions.dart';
import 'market_store.dart' show placeErrorProvider;
import 'glass_tab_bar.dart';
import '../water/water_store.dart';
import 'account_screens.dart';
import 'shop_home.dart';
import 'market_widgets.dart';
import 'trust_screens.dart';

/// One tab of the hub. Each app picks which tabs it shows.
class HubTab {
  final String emoji;
  final IconData icon;
  final String label;
  final Color? tint;
  final Widget Function(VoidCallback? onClose) build;
  const HubTab(this.emoji, this.icon, this.label, this.build, {this.tint});
}

/// Tabs every Nolifa Drop install has. Apps add their own (water, store).
List<HubTab> defaultDropTabs({VoidCallback? onMenu}) => [
      HubTab('🛒', Icons.storefront_rounded, 'Shop',
          (c) => ShopHomePage(onMenu: onMenu, onClose: c)),
      HubTab('🚨', Icons.notifications_active_rounded, 'Alerts', (c) => AlertsPage(onClose: c)),
    ];

/// Nolifa Drop: one network, several roles. Switching tabs switches who you are.
class MarketHub extends ConsumerStatefulWidget {
  /// Tabs to show. Defaults to [defaultDropTabs].
  final List<HubTab>? tabs;

  /// Show a close button on each page (when the hub is opened from another app).
  final bool showClose;

  const MarketHub({super.key, this.tabs, this.showClose = true});

  @override
  ConsumerState<MarketHub> createState() => _MarketHubState();
}

class _MarketHubState extends ConsumerState<MarketHub> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    // The server can refuse an order after the buyer has paid on screen. Say so.
    ref.listen<String?>(placeErrorProvider, (_, e) {
      if (e == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 6), behavior: SnackBarBehavior.floating));
      ref.read(placeErrorProvider.notifier).state = null;
    });
    final tabs = widget.tabs ?? defaultDropTabs(onMenu: () => openDropMenu(context));
    final i = _i.clamp(0, tabs.length - 1);
    final VoidCallback? close = widget.showClose ? () => Navigator.pop(context) : null;
    return Scaffold(
      extendBody: true,
      body: AppBackdrop(
        tint: tabs[i].tint ?? AppTheme.sprout,
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: KeyedSubtree(key: ValueKey(i), child: tabs[i].build(close)),
          ),
        ),
      ),
      bottomNavigationBar: GlassTabBar(
        index: i,
        tabs: [for (final t in tabs) (t.emoji, t.icon, t.label)],
        onTap: (n) {
          HapticFeedback.selectionClick();
          setState(() => _i = n);
        },
      ),
    );
  }
}

class AlertsPage extends ConsumerWidget {
  final VoidCallback? onClose;
  const AlertsPage({super.key, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(allAlertsProvider);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '🚨',
            title: 'Alerts',
            subtitle: 'Water, power, roads, outbreaks near you',
            accent: AppTheme.danger,
            trailing: HeaderActions(onClose: onClose),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
          sliver: SliverList.builder(
            itemCount: alerts.length,
            itemBuilder: (_, i) => Reveal(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.s3),
                child: AlertBanner(
                  alert: alerts[i],
                  onTap: () => handleAlert(context, ref, alerts[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
