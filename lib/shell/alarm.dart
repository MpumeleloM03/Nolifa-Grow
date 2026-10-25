import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        AlertBanner,
        MarketAlert,
        OrderStatus,
        Pill,
        Reveal,
        RingGauge,
        SectionTitle,
        WaterScreen,
        WaterStatusX,
        allAlertsProvider,
        handleAlert,
        marketProvider,
        waterProvider;
import '../models/outbreak_report.dart';
import '../screens/history_screen.dart';
import '../screens/livestock/livestock_home_screen.dart';
import '../screens/map_screen.dart';
import '../services/auth_service.dart';
import '../services/outbreak_service.dart';
import '../store/add_stock_sheet.dart';
import '../store/farm_water_section.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../weather/weather_card.dart';
import '../weather/weather_service.dart';
import '../weather/weather_threats.dart';
import 'alerts_tab.dart' show AreaOutbreak, buildAreaOutbreaks, showOutbreakDetails;

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Everything that needs the farmer's attention right now.
class AlarmItems {
  final List<WeatherThreat> weather;
  final List<MarketAlert> water;
  final List<MarketAlert> farm;
  final List<AreaOutbreak> urgent;
  final int ordersToSend;
  const AlarmItems(this.water, this.farm, this.urgent, this.ordersToSend, [this.weather = const []]);
  int get count => water.length + weather.length + farm.length + urgent.length + (ordersToSend > 0 ? 1 : 0);
}

final alarmProvider = Provider<AlarmItems>((ref) {
  final all = ref.watch(allAlertsProvider);
  final region = ref.watch(currentUserProvider)?.region ?? '';
  final live = ref.watch(outbreaksProvider).valueOrNull ?? const <OutbreakReport>[];
  final urgent = [
    for (final o in buildAreaOutbreaks(live, demo: ref.watch(marketProvider.select((s) => s.demoMode))))
      if (o.severity == 'red' && o.region == region) o
  ];
  final toSend = ref.watch(marketProvider.select((s) => s.farmOrders.where((o) => o.status == OrderStatus.newOrder).length));
  return AlarmItems(
    [for (final a in all) if (a.id.startsWith('w-')) a],
    [for (final a in all) if (a.farmSide) a],
    urgent,
    toSend,
    ref.watch(weatherThreatsProvider),
  );
});

/// The red alarm in the top left of Alerts. It pings while anything needs the
/// farmer, so they see at a glance that this is where to look.
class AlarmButton extends ConsumerStatefulWidget {
  const AlarmButton({super.key});

  @override
  ConsumerState<AlarmButton> createState() => _AlarmButtonState();
}

class _AlarmButtonState extends ConsumerState<AlarmButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ping =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(alarmProvider.select((a) => a.count));
    final active = n > 0;
    final color = active ? AppTheme.danger : AppTheme.textTertiary;
    return Semantics(
      button: true,
      label: active ? 'Alarm, $n things need your attention' : 'Alarm, nothing needs you',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AlarmScreen()));
        },
        child: SizedBox(
          width: 64,
          height: 64,
          child: AnimatedBuilder(
            animation: _ping,
            builder: (_, __) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (active)
                for (final phase in const [0.0, 0.5])
                  Builder(builder: (_) {
                    final t = (_ping.value + phase) % 1.0;
                    return Container(
                      width: 44 + 30 * t,
                      height: 44 + 30 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.7 * (1 - t)), width: 3),
                      ),
                    );
                  }),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: active ? 0.9 : 0.2),
                  boxShadow: active
                      ? [BoxShadow(color: AppTheme.danger.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 1)]
                      : null,
                ),
                child: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    color: Colors.white, size: 24),
              ),
              if (active)
                Positioned(
                  right: 6,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text('$n',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFB00020), fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The alarm page: water first and biggest, then everything else.
class AlarmScreen extends ConsumerWidget {
  const AlarmScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(alarmProvider);
    final w = ref.watch(waterProvider);
    final zone = w.myZone;
    final forecast = zone == null ? null : w.forecastOf(zone.id);

    void openFarmAlert(MarketAlert x) => _push(
        context,
        x.id == 'a-armyworm'
            ? const HistoryScreen()
            : (x.id == 'a-fmd' ? const LivestockHomeScreen() : const MapScreen()));

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.danger,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Alarm'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  if (a.count == 0)
                    GlassCard(
                      child: Row(children: [
                        const Glyph('✅', size: 34),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text('Nothing needs you right now. Water is fine, no urgent outbreaks, no orders waiting.',
                              style: AppTheme.callout),
                        ),
                      ]),
                    ),
                  // WATER: the biggest card, because a dry tank is the fastest way to lose a herd or a crop.
                  if (a.water.isNotEmpty && zone != null) ...[
                    const SectionTitle('💧', 'Water'),
                    Reveal(
                      child: GlassCard(
                        tint: AppTheme.danger.withValues(alpha: 0.14),
                        padding: const EdgeInsets.all(AppTheme.s5),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            RingGauge(
                              value: zone.level / 100,
                              size: 84,
                              color: zone.level < 25 ? AppTheme.danger : AppTheme.warn,
                              center: Text('${zone.level.round()}%', style: AppTheme.title3),
                            ),
                            const SizedBox(width: AppTheme.s4),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${zone.name} water is ${zone.status.label.toLowerCase()}', style: AppTheme.title3),
                                if (forecast?.daysToCritical != null)
                                  Text('About ${forecast!.daysToCritical!.toStringAsFixed(1)} days until critical',
                                      style: AppTheme.callout),
                                Text(zone.provider, style: AppTheme.caption),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: AppTheme.s4),
                          for (final x in a.water)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.s2),
                              child: Text('${x.title}. ${x.body}', style: AppTheme.footnote),
                            ),
                          GlassButton(
                            label: 'Vote and add to the community voice',
                            icon: Icons.how_to_vote_rounded,
                            accent: AppTheme.danger,
                            onPressed: () => _push(context, const WaterScreen(extraSections: [FarmWaterSection()])),
                          ),
                        ]),
                      ),
                    ),
                  ],
                  if (a.weather.isNotEmpty) ...[
                    const SectionTitle('🌦️', 'Weather'),
                    for (final t in a.weather)
                      Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: ThreatCard(t)),
                  ],
                  if (a.ordersToSend > 0) ...[
                    const SectionTitle('📦', 'Orders'),
                    GlassCard(
                      tint: AppTheme.warn.withValues(alpha: 0.12),
                      child: Row(children: [
                        Icon(Icons.local_shipping_rounded, color: AppTheme.warn),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text('${a.ordersToSend} order${a.ordersToSend == 1 ? '' : 's'} waiting to be packed and sent out',
                              style: AppTheme.headline),
                        ),
                      ]),
                    ),
                  ],
                  if (a.urgent.isNotEmpty) ...[
                    const SectionTitle('🚨', 'Urgent outbreaks in your area'),
                    for (final o in a.urgent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: GlassCard(
                          tint: AppTheme.danger.withValues(alpha: 0.10),
                          onTap: () => showOutbreakDetails(context, o),
                          child: Row(children: [
                            Glyph(o.kind == OutbreakKind.livestock ? '🐄' : '🌿', size: 26),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(o.disease, style: AppTheme.headline),
                                Text('${o.reports} reports in ${o.region}', style: AppTheme.footnote),
                              ]),
                            ),
                            Pill(o.severityLabel, color: o.color),
                          ]),
                        ),
                      ),
                  ],
                  if (a.farm.isNotEmpty) ...[
                    const SectionTitle('🌾', 'On your farm'),
                    for (final x in a.farm)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s3),
                        child: AlertBanner(
                          alert: x,
                          onTap: () => handleAlert(context, ref, x,
                              openListing: () => startAddStock(context, ref, rescue: true),
                              onFarmAlert: openFarmAlert),
                        ),
                      ),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
