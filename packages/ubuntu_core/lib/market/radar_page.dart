import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'trust_screens.dart';

/// Supply Risk Radar: the business-facing side of Nolifa Drop.
///
/// Retailers, processors and restaurants see verified disease risk around the
/// farms that supply them, a 7-day forecast, and backup suppliers. Farmers
/// never see this screen; businesses never see unverified reports.
class RadarPage extends ConsumerWidget {
  final VoidCallback? onClose;
  const RadarPage({super.key, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final high = s.highRiskCount;
    final watch = suppliers.where((x) => s.riskOf(x).$1 == Risk.watch).length;
    final clear = suppliers.length - high - watch;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '📡',
            title: 'Supply Radar',
            subtitle: 'Verified disease risk across your suppliers',
            accent: AppTheme.sprout,
            trailing: HeaderActions(onClose: onClose),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: GlassCard(
                tint: (high > 0 ? AppTheme.danger : AppTheme.sprout).withValues(alpha: 0.12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('FreshCo Retail (demo)', style: AppTheme.headline),
                        Text('${s.bizPlan.label} plan  •  ${suppliers.length} suppliers monitored',
                            style: AppTheme.footnote),
                      ]),
                    ),
                    Pill(high > 0 ? '$high need action' : 'All clear',
                        color: high > 0 ? AppTheme.danger : AppTheme.sprout,
                        icon: high > 0 ? Icons.warning_amber_rounded : Icons.check_circle_rounded),
                  ]),
                  const SizedBox(height: AppTheme.s4),
                  Row(children: [
                    _Count('$high', 'High risk', Risk.high.color),
                    _Count('$watch', 'Watch', Risk.watch.color),
                    _Count('$clear', 'Clear', Risk.clear.color),
                  ]),
                ]),
              ),
            ),
            const SectionTitle('🏭', 'Your suppliers'),
            for (var i = 0; i < suppliers.length; i++)
              Reveal(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s3),
                  child: _SupplierCard(supplier: suppliers[i]),
                ),
              ),
            const SectionTitle('🔮', 'Forecast alerts'),
            const Reveal(
              child: _ForecastTile('🌧️', 'Rift Valley fever risk rising in the Midlands',
                  'Heavy rain forecast raises mosquito-borne risk for cattle. 62% over 14 days.'),
            ),
            const SizedBox(height: AppTheme.s3),
            const Reveal(
              index: 1,
              child: _ForecastTile('🔥', 'Heat stress on poultry in the Berea belt',
                  'Five days above 34°C. Expect lower layer output and higher mortality.'),
            ),
            const SectionTitle('💼', 'Plans for business'),
            for (final p in BizPlan.values)
              Reveal(
                index: p.index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s3),
                  child: GlassCard(
                    tint: s.bizPlan == p ? AppTheme.sprout.withValues(alpha: 0.14) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(p.label, style: AppTheme.title3)),
                        if (s.bizPlan == p) Pill('Current plan', color: AppTheme.sprout),
                      ]),
                      Text(p.price, style: AppTheme.title2.copyWith(color: AppTheme.sprout)),
                      const SizedBox(height: AppTheme.s2),
                      for (final perk in p.perks)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Icon(Icons.check_circle_rounded, size: 15, color: AppTheme.sprout),
                            const SizedBox(width: AppTheme.s2),
                            Expanded(child: Text(perk, style: AppTheme.footnote)),
                          ]),
                        ),
                      if (s.bizPlan != p) ...[
                        const SizedBox(height: AppTheme.s3),
                        GlassButton(
                          label: p == BizPlan.enterprise ? 'Talk to us' : 'Choose ${p.label}',
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            store.setBizPlan(p);
                          },
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            const SectionTitle('🤝', 'How farmers are protected'),
            const Reveal(
              child: GlassCard(
                child: Column(children: [
                  _Point('Only verified cases count. An unconfirmed report never changes a supplier\'s rating.'),
                  _Point('Suppliers join your network and agree to share their status with you. Nothing is shared without that agreement.'),
                  _Point('A risk rating triggers a temporary reroute, not a delisting. Volume returns when the vet clears the farm.'),
                  _Point('Farms in an outbreak get priority vet support and are pointed to FNB cover for lost income.'),
                  _Point('Businesses only see district-level data for farms outside their network.'),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final String n, label;
  final Color color;
  const _Count(this.n, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          CountUp(double.parse(n),
              prefix: '', style: AppTheme.largeTitle.copyWith(color: color)),
          Text(label, style: AppTheme.caption),
        ]),
      );
}

class _ForecastTile extends StatelessWidget {
  final String emoji, title, body;
  const _ForecastTile(this.emoji, this.title, this.body);

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.headline),
              const SizedBox(height: 2),
              Text(body, style: AppTheme.footnote),
            ]),
          ),
        ]),
      );
}

class _Point extends StatelessWidget {
  final String text;
  const _Point(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.shield_rounded, size: 15, color: AppTheme.sprout),
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text(text, style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary))),
        ]),
      );
}

class _SupplierCard extends ConsumerWidget {
  final Supplier supplier;
  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final (risk, why) = s.riskOf(supplier);
    final rerouted = s.rerouted.contains(supplier.id);
    final color = rerouted ? AppTheme.sprout : risk.color;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      tint: risk == Risk.high && !rerouted ? AppTheme.danger.withValues(alpha: 0.10) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(supplier.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(supplier.name, style: AppTheme.headline),
              Text('${supplier.product}  •  ${supplier.district}', style: AppTheme.footnote),
            ]),
          ),
          Pill(rerouted ? 'Rerouted' : risk.label, color: color),
        ]),
        const SizedBox(height: AppTheme.s3),
        _ForecastBars(values: supplier.forecast),
        const SizedBox(height: AppTheme.s2),
        Text(why, style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
        if (risk != Risk.clear) ...[
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            Expanded(
              child: GhostButton(
                label: rerouted ? 'Undo reroute' : 'Reroute volume',
                icon: Icons.alt_route_rounded,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(marketProvider.notifier).reroute(supplier.id, !rerouted);
                },
              ),
            ),
            const SizedBox(width: AppTheme.s2),
            Expanded(
              child: GhostButton(
                label: 'Backups',
                icon: Icons.swap_horiz_rounded,
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _BackupSheet(supplier: supplier),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ForecastBars extends StatelessWidget {
  final List<int> values;
  const _ForecastBars({required this.values});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 58,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: values[i] / 100),
                  duration: Duration(milliseconds: 500 + i * 90),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Container(
                    height: 4 + 34 * v,
                    decoration: BoxDecoration(
                      color: (values[i] >= 70
                              ? Risk.high.color
                              : values[i] >= 40
                                  ? Risk.watch.color
                                  : Risk.clear.color)
                          .withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(days[i], style: AppTheme.caption.copyWith(fontSize: 9)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _BackupSheet extends ConsumerWidget {
  final Supplier supplier;
  const _BackupSheet({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final alts = alternatives.where((a) => a.product == supplier.product).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.sheet,
        borderRadius: const BorderRadius.vertical(top: const Radius.circular(AppTheme.rCard)),
      ),
      padding: const EdgeInsets.all(AppTheme.s6),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🔁 Backup suppliers for ${supplier.product}', style: AppTheme.title2),
        const SizedBox(height: 4),
        Text('FNB-verified farms outside ${supplier.district} that can absorb volume while ${supplier.name} is cleared.',
            style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s4),
        if (alts.isEmpty) Text('No verified backups for this product yet.', style: AppTheme.callout),
        for (final a in alts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s3),
            child: GlassCard(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.name, style: AppTheme.headline),
                    Text('${a.district}  •  ${a.km} km  •  ${a.capacity}% capacity  •  ${a.premium}',
                        style: AppTheme.footnote),
                  ]),
                ),
                GestureDetector(
                  onTap: s.quotes.contains(a.id)
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          ref.read(marketProvider.notifier).requestQuote(a.id);
                        },
                  child: Pill(s.quotes.contains(a.id) ? 'Quote sent' : 'Request quote',
                      color: AppTheme.sprout,
                      icon: s.quotes.contains(a.id) ? Icons.check_rounded : Icons.send_rounded),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
