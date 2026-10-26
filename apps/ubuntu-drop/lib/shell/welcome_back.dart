import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show OrderStatus, WaterStatusX, marketProvider, notifierProvider, waterProvider, welcomeShownProvider;

import '../auth/auth_service.dart';

/// The line a customer opens the app to: orders on the way, then water, then
/// a nudge to the shop.
String customerUpdate(int ordersOnTheWay, String? lowWater) {
  final bits = <String>[
    if (ordersOnTheWay > 0) '$ordersOnTheWay order${ordersOnTheWay == 1 ? ' is' : 's are'} on the way',
    if (lowWater != null) lowWater,
  ];
  return bits.isEmpty ? 'Fresh produce is waiting from farms near you.' : '${bits.join('. ')}.';
}

/// Sends "Welcome back, <name>" as a notification the moment the app opens.
/// Notifications are assumed on in Settings.
class WelcomeBackHost extends ConsumerStatefulWidget {
  final Widget child;
  const WelcomeBackHost({super.key, required this.child});

  @override
  ConsumerState<WelcomeBackHost> createState() => _WelcomeBackHostState();
}

class _WelcomeBackHostState extends ConsumerState<WelcomeBackHost> {
  @override
  void initState() {
    super.initState();
    // Give the order and water data a moment to load so the update is true.
    Future.delayed(const Duration(milliseconds: 1500), _send);
  }

  void _send() {
    if (!mounted || ref.read(welcomeShownProvider)) return;
    ref.read(welcomeShownProvider.notifier).state = true;
    final raw = ref.read(currentUserProvider)?.name.trim() ?? '';
    final name = raw.isEmpty ? 'neighbour' : raw.split(' ').first;
    final onTheWay = ref
        .read(marketProvider)
        .myOrders
        .where((o) => o.status != OrderStatus.delivered)
        .length;
    final zone = ref.read(waterProvider).myZone;
    final low = zone != null && zone.status.canRequestHelp
        ? '${zone.name} water is ${zone.status.label.toLowerCase()} (${zone.level.round()}%)'
        : null;
    ref
        .read(notifierProvider)
        .show(title: 'Welcome back, $name', body: customerUpdate(onTheWay, low));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
