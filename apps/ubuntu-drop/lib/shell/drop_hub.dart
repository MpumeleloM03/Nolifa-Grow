import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../auth/auth_service.dart';
import 'account_sheet.dart';
import 'welcome_back.dart';

/// Nolifa Drop has three tabs: Shop, Water, Alerts. Everything else a
/// customer needs (orders, wallet, settings, help) is in the menu on Shop.
List<HubTab> dropTabs({VoidCallback? onMenu}) => [
      HubTab('🛒', Icons.storefront_rounded, 'Shop',
          (c) => ShopHomePage(onMenu: onMenu)),
      HubTab('💧', Icons.water_drop_rounded, 'Water', (c) => WaterPage(onClose: c)),
      HubTab('🚨', Icons.notifications_active_rounded, 'Alerts',
          (c) => AlertsPage(onClose: c)),
    ];

/// The shared hub with a menu button on Shop.
class DropHub extends StatelessWidget {
  const DropHub({super.key});

  @override
  Widget build(BuildContext context) => WelcomeBackHost(
        child: LowWaterPromptHost(
        child: Builder(
        builder: (context) => MarketHub(
          showClose: false,
          tabs: dropTabs(
            onMenu: () => openDropMenu(context, extra: [
              MenuItem(Icons.manage_accounts_rounded, 'Account and app mode',
                  () => showAccountSheet(context),
                  detail: 'Demo or live, who you are signed in as'),
              MenuItem(Icons.logout_rounded, 'Sign out', () {
                final container = ProviderScope.containerOf(context);
                container.read(authServiceProvider).signOut();
                Navigator.of(context).popUntil((r) => r.isFirst);
              }, color: AppTheme.danger),
            ]),
          ),
        ),
      )));
}
