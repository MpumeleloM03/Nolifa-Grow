import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../auth/auth_service.dart';
import '../home/driver_home.dart';
import 'account_page.dart';
import 'earnings_page.dart';

/// Nolifa Delivery has three tabs: Jobs, Earnings and Account.
List<HubTab> deliveryTabs() => [
      HubTab('🛵', Icons.two_wheeler_rounded, 'Jobs', (c) => const DriverHome(),
          tint: AppTheme.livestockAccent),
      HubTab('💸', Icons.payments_rounded, 'Earnings', (c) => const EarningsPage()),
      HubTab('👤', Icons.person_rounded, 'Account', (c) => const AccountPage()),
    ];

/// The driver's home after sign-in.
class DeliveryHub extends StatelessWidget {
  const DeliveryHub({super.key});

  @override
  Widget build(BuildContext context) =>
      MarketHub(showClose: false, tabs: deliveryTabs());
}

/// Signs out and clears any pages stacked above the sign-in gate.
void signOutDriver(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  ref.read(authServiceProvider).signOut();
  Navigator.of(context).popUntil((r) => r.isFirst);
}
