import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../roads/road_screens.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'trust_screens.dart';

/// Opens turn-by-turn directions to a place. The driver app supplies the real
/// one (it needs a maps plugin); returns false when nothing could be opened.
/// Draws the route for an accepted job: the driver, the farm and the customer.
/// The driver app supplies it (it needs a map plugin). Null shows no map.
final jobMapProvider = Provider<Widget Function(Order order)?>((ref) => null);

/// The live map on the customer's tracking page. The customer app supplies it
/// (it needs a map plugin). Null keeps the drawn sketch.
final trackMapProvider = Provider<Widget Function(Order order)?>((ref) => null);

final navigateProvider =
    Provider<Future<bool> Function(String destination)>((ref) => (_) async => false);

/// Takes a proof photo with the camera. Returns false if the driver backed out.
/// The default has no camera and always accepts, so the app still works in tests.
final proofPhotoProvider = Provider<Future<bool> Function()>((ref) => () async => true);

class DrivePage extends ConsumerWidget {
  final VoidCallback? onClose;
  const DrivePage({super.key, this.onClose});

  void _sos(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('🚨 Safety line', style: AppTheme.title3),
        content: Text(
            'Your live location and job details are being shared with the Nolifa Drop safety team. In an emergency call 10111 or 112.',
            style: AppTheme.callout),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AppTheme.sprout))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final jobs = s.openJobs;
    final mine = s.myJobs;
    final done = s.orders.where((o) => o.driverIsMe && o.released).length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '🛵',
            title: 'Drive',
            subtitle: 'Earn on your own street',
            accent: AppTheme.livestockAccent,
            trailing: HeaderActions(onClose: onClose),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: GlassCard(
                tint: s.driverOnline
                    ? AppTheme.sprout.withValues(alpha: 0.14)
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.driverOnline ? '🟢 You are online' : '⚫ You are offline',
                                style: AppTheme.headline),
                            Row(children: [
                              Icon(Icons.verified_rounded,
                                  size: 14, color: AppTheme.sprout),
                              const SizedBox(width: 4),
                              Text('FNB-verified driver', style: AppTheme.caption),
                            ]),
                          ]),
                    ),
                    Switch(
                      value: s.driverOnline,
                      activeThumbColor: AppTheme.sprout,
                      onChanged: (_) {
                        HapticFeedback.mediumImpact();
                        if (!s.driverVerified && !s.driverOnline) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const VerifyScreen(role: KycRole.driver)));
                          return;
                        }
                        store.toggleOnline();
                      },
                    ),
                  ]),
                  const SizedBox(height: AppTheme.s4),
                  Text('Earned', style: AppTheme.caption),
                  CountUp(s.driverEarned,
                      decimals: 0,
                      style: AppTheme.largeTitle.copyWith(color: AppTheme.livestockAccent)),
                  const SizedBox(height: AppTheme.s2),
                  Row(children: [
                    Pill('$done deliveries', color: AppTheme.sprout, icon: Icons.local_shipping_rounded),
                    const SizedBox(width: AppTheme.s2),
                    Pill('4.9 ★', color: AppTheme.livestockAccent),
                  ]),
                ]),
              ),
            ),
            if (!s.driverVerified) ...[
              const SizedBox(height: AppTheme.s3),
              Reveal(
                index: 1,
                child: GlassCard(
                  tint: AppTheme.warn.withValues(alpha: 0.12),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const VerifyScreen(role: KycRole.driver))),
                  child: Row(children: [
                    const Text('🪪', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Get verified to start earning', style: AppTheme.headline),
                        Text('${driverSteps.length - s.driverKyc.length} of ${driverSteps.length} checks left. No verification, no jobs.',
                            style: AppTheme.footnote),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: AppTheme.s3),
            Reveal(
              index: 2,
              child: Row(children: [
                Expanded(
                  child: GhostButton(
                    label: 'SOS',
                    icon: Icons.sos_rounded,
                    onPressed: () => _sos(context),
                  ),
                ),
                const SizedBox(width: AppTheme.s2),
                Expanded(
                  child: GhostButton(
                    label: 'Wallet',
                    icon: Icons.account_balance_wallet_rounded,
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const WalletScreen())),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: AppTheme.s3),
            const Reveal(index: 3, child: RoadAlertsCard()),
            if (mine.isNotEmpty) ...[
              const SectionTitle('🚦', 'Your active job'),
              for (final o in mine)
                Reveal(
                  child: _ActiveJob(order: o),
                ),
            ],
            SectionTitle('📍', 'Jobs near you',
                trailing: s.driverOnline
                    ? Pill('${jobs.length} open', color: AppTheme.sprout)
                    : null),
            if (!s.driverOnline)
              Reveal(
                child: GlassCard(
                  child: Row(children: [
                    const Text('😴', style: TextStyle(fontSize: 30)),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(
                        child: Text('Go online to see delivery jobs around you.',
                            style: AppTheme.callout)),
                  ]),
                ),
              )
            else if (jobs.isEmpty)
              Text('No open jobs right now. New ones appear as people order.',
                  style: AppTheme.callout)
            else
              for (var i = 0; i < jobs.length; i++)
                Reveal(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppTheme.s4),
                      child: Column(children: [
                        Row(children: [
                          Text(jobs[i].lines.first.emoji,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: AppTheme.s3),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${jobs[i].driverPickup}  →  ${jobs[i].dropArea}',
                                      style: AppTheme.headline),
                                  Text(
                                      '${jobs[i].lines.fold<int>(0, (a, l) => a + l.qty)} items  •  ${jobs[i].method.label}',
                                      style: AppTheme.footnote),
                                ]),
                          ),
                          Text(rand(jobs[i].driverPay, decimals: 0),
                              style: AppTheme.title3
                                  .copyWith(color: AppTheme.livestockAccent)),
                        ]),
                        const SizedBox(height: AppTheme.s3),
                        GlassButton(
                          label: 'Accept job',
                          icon: Icons.check_rounded,
                          accent: AppTheme.livestockAccent,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            store.accept(jobs[i].id);
                          },
                        ),
                      ]),
                    ),
                  ),
                ),
          ]),
        ),
      ],
    );
  }
}

/// Asks for the buyer's 4-digit PIN at the door. Delivery, and the payout,
/// only happen when it matches. Used by drivers and by farms that deliver
/// their own orders.
Future<void> askCustomerPin(BuildContext context, MarketStore store, Order order) async {
  final c = TextEditingController();
  String? err;
  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('🔑 Customer PIN', style: AppTheme.title3),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ask the customer for their 4-digit PIN. Payment releases only after it matches. After $maxPinAttempts wrong tries the order locks.',
              style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s3),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: AppTheme.title2,
            decoration: InputDecoration(errorText: err, counterText: ''),
          ),
          if (order.pin != null)
            Text('Demo PIN: ${order.pin}', style: AppTheme.caption),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () {
              final r = store.tryPin(order.id, c.text);
              if (r.delivered) {
                Navigator.pop(ctx);
              } else if (r.locked) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Too many wrong PINs. The order is locked, a dispute is open and the money stays frozen.'),
                    behavior: SnackBarBehavior.floating));
              } else {
                setS(() => err = 'That PIN does not match. ${r.attemptsLeft} ${r.attemptsLeft == 1 ? 'try' : 'tries'} left');
              }
            },
            child: Text('Confirm', style: TextStyle(color: AppTheme.sprout)),
          ),
        ],
      ),
    ),
  );
}

class _ActiveJob extends ConsumerWidget {
  final Order order;
  const _ActiveJob({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(marketProvider.notifier);
    final toFarm = order.status == OrderStatus.assigned;
    final destination = toFarm ? order.driverPickup : order.dropArea;

    Future<void> navigate() async {
      HapticFeedback.selectionClick();
      final ok = await ref.read(navigateProvider)(destination);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open maps. Head to $destination.'),
            behavior: SnackBarBehavior.floating));
      }
    }

    Future<void> next() async {
      HapticFeedback.heavyImpact();
      // Pickup and drop-off both need a photo as proof, taken with the camera.
      final shot = await ref.read(proofPhotoProvider)();
      if (!shot) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('A photo is needed as proof first.'),
              behavior: SnackBarBehavior.floating));
        }
        return;
      }
      if (!context.mounted) return;
      toFarm ? store.pickedUp(order.id) : await askCustomerPin(context, store, order);
    }

    return GlassCard(
      tint: AppTheme.livestockAccent.withValues(alpha: 0.12),
      child: Column(children: [
        Row(children: [
          Text(toFarm ? '🌾' : '🏠', style: const TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(toFarm ? 'Go to ${order.driverPickup}' : 'Deliver to ${order.dropArea}',
                  style: AppTheme.headline),
              Text('${order.id}  •  you earn ${rand(order.driverPay)}',
                  style: AppTheme.footnote),
            ]),
          ),
        ]),
        if (ref.watch(jobMapProvider) != null) ...[
          const SizedBox(height: AppTheme.s3),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            child: SizedBox(height: 210, child: ref.watch(jobMapProvider)!(order)),
          ),
        ],
        const SizedBox(height: AppTheme.s3),
        GlassButton(
          label: toFarm ? 'Navigate to the farm' : 'Navigate to the customer',
          icon: Icons.navigation_rounded,
          accent: AppTheme.plantAccent,
          onPressed: navigate,
        ),
        const SizedBox(height: AppTheme.s2),
        GlassButton(
          label: toFarm ? 'Picked up: take photo' : 'Delivered: take photo, then PIN',
          icon: Icons.photo_camera_rounded,
          accent: AppTheme.livestockAccent,
          onPressed: next,
        ),
      ]),
    );
  }
}
