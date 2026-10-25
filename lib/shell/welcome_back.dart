import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show OrderStatus, WaterStatusX, marketProvider, notifierProvider, waterProvider, welcomeShownProvider;
import '../services/auth_service.dart';
import '../weather/weather_service.dart';

/// The line a farmer wakes up to: orders waiting and water, in that order.
String farmerUpdate(int ordersToSend, String? lowWater, int urgentAround, [String? weather]) {
  final bits = <String>[
    if (weather != null) weather,
    if (ordersToSend > 0) '$ordersToSend order${ordersToSend == 1 ? '' : 's'} to send out',
    if (lowWater != null) lowWater,
    if (urgentAround > 0) '$urgentAround urgent outbreak${urgentAround == 1 ? '' : 's'} near you',
  ];
  return bits.isEmpty ? 'Everything looks calm on the farm.' : '${bits.join('. ')}.';
}

/// Sends "Welcome back, <name>" as a notification the moment the app opens,
/// with the update that matters. Notifications are assumed on in Settings.
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
    // Give the water and order data a moment to load so the update is true.
    Future.delayed(const Duration(milliseconds: 1500), _send);
  }

  void _send() {
    if (!mounted || ref.read(welcomeShownProvider)) return;
    ref.read(welcomeShownProvider.notifier).state = true;
    final user = ref.read(currentUserProvider);
    final raw = user?.name.trim() ?? '';
    final community = user?.isCommunity ?? false;
    final name = raw.isEmpty ? (community ? 'neighbour' : 'farmer') : raw.split(' ').first;
    final threats = ref.read(weatherThreatsProvider);
    final m = ref.read(marketProvider);
    final toSend = community ? 0 : m.farmOrders.where((o) => o.status == OrderStatus.newOrder).length;
    final w = ref.read(waterProvider);
    final zone = w.myZone;
    final low = zone != null && zone.status.canRequestHelp
        ? '${zone.name} water is ${zone.status.label.toLowerCase()} (${zone.level.round()}%)'
        : null;
    var body = farmerUpdate(toSend, low, 0, threats.isEmpty ? null : threats.first.title);
    if (community) body = body.replaceFirst('on the farm', 'in your area');
    ref.read(notifierProvider).show(title: 'Welcome back, $name', body: body);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
