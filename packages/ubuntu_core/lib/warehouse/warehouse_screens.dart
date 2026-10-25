import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_models.dart' show Category, CategoryX;
import '../market/market_store.dart';
import '../market/market_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'warehouse_models.dart';
import 'warehouse_store.dart';

import '../tr_text.dart' show Text;
import '../tr.dart' show trn;
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _d(DateTime t) => '${t.day} ${_months[t.month - 1]}';
String _t(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _q(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

Color _zoneColor(StorageZone z) => switch (z) {
      StorageZone.frozen => const Color(0xFF7FB6FF),
      StorageZone.chilled => const Color(0xFF5AD1E6),
      StorageZone.cool => const Color(0xFF8FD694),
      StorageZone.ambient => const Color(0xFFE8A33D),
    };

/// The label that goes on a stored lot: tag, product, farm, room and bay,
/// temperature at check-in and use-by date.
class LotTagCard extends StatelessWidget {
  final StockLot lot;
  final DateTime now;
  final bool atRisk;
  const LotTagCard(this.lot, {super.key, required this.now, this.atRisk = false});

  @override
  Widget build(BuildContext context) {
    final days = lot.daysLeft(now);
    final soon = lot.inStock && days <= 2;
    final (statusText, statusColor) = switch (lot.status) {
      LotStatus.expected => ('Expected ${_d(lot.expectedAt)}', AppTheme.warn),
      LotStatus.stored => atRisk ? ('Room out of range', AppTheme.danger) : ('In storage', AppTheme.ok),
      LotStatus.rejected => ('Rejected', AppTheme.danger),
      LotStatus.emptied => ('All sent out', AppTheme.textTertiary),
      LotStatus.expired => ('Written off', AppTheme.danger),
    };
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      radius: AppTheme.rControl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _zoneColor(lot.zone).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _zoneColor(lot.zone)),
            ),
            child: Text(lot.tag ?? 'No tag yet', style: AppTheme.footnote.copyWith(fontWeight: FontWeight.w800, fontFamily: 'Menlo')),
          ),
          const Spacer(),
          Pill(statusText, color: statusColor),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text(lot.productName, style: AppTheme.headline),
        Text(
            lot.inStock
                ? '${_q(lot.remaining)} of ${_q(lot.qty)} ${lot.unit} left  -  ${lot.farmName}'
                : '${_q(lot.qty)} ${lot.unit}  -  ${lot.farmName}',
            style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s2),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill('${lot.zone.label} ${lot.zone.band}', color: _zoneColor(lot.zone), icon: Icons.ac_unit_rounded),
          if (lot.bay != null) Pill('Bay ${lot.bay}', color: AppTheme.textSecondary),
          if (lot.receivedTempC != null) Pill('In at ${lot.receivedTempC!.toStringAsFixed(1)} C', color: AppTheme.textSecondary),
          Pill(soon ? 'Use by ${_d(lot.useBy)} (${days <= 0 ? 'today' : '$days d'})' : 'Use by ${_d(lot.useBy)}',
              color: soon ? AppTheme.warn : AppTheme.textSecondary),
        ]),
        if (lot.note.isNotEmpty && lot.status == LotStatus.rejected)
          Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(lot.note, style: AppTheme.footnote.copyWith(color: AppTheme.danger))),
        if (lot.events.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('History', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
              children: [
                for (final e in lot.events.reversed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${_d(e.at)} ${_t(e.at)}  ${e.text}', style: AppTheme.caption),
                    ),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ farmer side

/// What a farm has in the Nolifa warehouse, and the form to deposit more.
class FarmerWarehouseScreen extends ConsumerWidget {
  const FarmerWarehouseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(marketUidProvider);
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    final mine = [...wh.forFarmer(uid)]..sort((a, b) => b.expectedAt.compareTo(a.expectedAt));
    final stored = mine.where((l) => l.inStock).toList();
    final byProduct = <String, double>{};
    for (final l in stored) {
      byProduct['${l.productName} (${l.unit})'] = (byProduct['${l.productName} (${l.unit})'] ?? 0) + l.remaining;
    }
    return Scaffold(
      body: AppBackdrop(
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
                title: const Text('Nolifa warehouse'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Deposit your supply', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text(
                      'Bring stock to the Nolifa warehouse and it is checked in, tagged and kept in a cold room at the right temperature. '
                      'Buyers far away are served from here, so you do not drive every order out yourself. Everything is logged and you see it here.',
                      style: AppTheme.callout),
                  const SizedBox(height: AppTheme.s4),
                  GlassButton(
                    label: 'Deposit goods',
                    icon: Icons.add_box_rounded,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const _DepositSheet(),
                    ),
                  ),
                  if (!wh.shared)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.s3),
                      child: Text(
                          'Prototype: the warehouse desk sees your deposits on this phone only. They are shared once the backend is on.',
                          style: AppTheme.footnote),
                    ),
                  if (byProduct.isNotEmpty) ...[
                    const SectionTitle('🧊', 'In storage now'),
                    GlassCard(
                      child: Column(children: [
                        for (final e in byProduct.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(child: Text(e.key, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary))),
                              Text(_q(e.value), style: AppTheme.headline),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                  const SectionTitle('🏷️', 'Your deposits'),
                  if (mine.isEmpty)
                    GlassCard(child: Text('Nothing deposited yet.', style: AppTheme.callout))
                  else
                    for (final l in mine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s3),
                        child: LotTagCard(l, now: now, atRisk: wh.zoneAtRisk(l.hub, l.zone)),
                      ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepositSheet extends ConsumerStatefulWidget {
  const _DepositSheet();

  @override
  ConsumerState<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends ConsumerState<_DepositSheet> {
  final _name = TextEditingController();
  final _qty = TextEditingController();
  Category _cat = Category.meat;
  StorageZone _zone = StorageZone.chilled;
  int _useByDays = 5;
  int _arriveDays = 0;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', '.'));
    if (_name.text.trim().isEmpty) return setState(() => _error = 'What are you bringing?');
    if (qty == null || qty <= 0) return setState(() => _error = 'Enter how much, in kg or units');
    final now = DateTime.now();
    final lot = await ref.read(warehouseProvider.notifier).announce(
          productName: _name.text,
          category: _cat,
          unit: _cat == Category.meat ? 'kg' : 'unit',
          qty: qty,
          zone: _zone,
          useBy: now.add(Duration(days: _useByDays)),
          expectedAt: now.add(Duration(days: _arriveDays)),
        );
    if (!mounted) return;
    if (lot == null) return setState(() => _error = 'Check the room and the use-by date');
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final zones = StorageZone.allowedFor(_cat);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.sheet, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
        padding: const EdgeInsets.all(AppTheme.s6),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Deposit goods', style: AppTheme.title2),
              Text('The warehouse checks them in when they arrive.', style: AppTheme.footnote),
              const SizedBox(height: AppTheme.s4),
              GlassField(controller: _name, label: 'Product (for example Beef mince)', icon: Icons.inventory_2_rounded),
              const SizedBox(height: AppTheme.s3),
              GlassField(controller: _qty, label: 'How much (kg or units)', icon: Icons.scale_rounded, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: AppTheme.s3),
              Text('Kind', style: AppTheme.footnote),
              Wrap(spacing: AppTheme.s2, children: [
                for (final c in Category.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _cat == c,
                    onSelected: (_) => setState(() {
                      _cat = c;
                      _zone = StorageZone.defaultFor(c);
                    }),
                  ),
              ]),
              const SizedBox(height: AppTheme.s3),
              Text('Storage room', style: AppTheme.footnote),
              Wrap(spacing: AppTheme.s2, children: [
                for (final z in zones)
                  ChoiceChip(label: Text('${z.label} (${z.band})'), selected: _zone == z, onSelected: (_) => setState(() => _zone = z)),
              ]),
              const SizedBox(height: AppTheme.s3),
              Text('Use by', style: AppTheme.footnote),
              Wrap(spacing: AppTheme.s2, children: [
                for (final d in const [2, 5, 7, 14, 30, 90])
                  ChoiceChip(label: Text('$d days'), selected: _useByDays == d, onSelected: (_) => setState(() => _useByDays = d)),
              ]),
              const SizedBox(height: AppTheme.s3),
              Text('Bringing it', style: AppTheme.footnote),
              Wrap(spacing: AppTheme.s2, children: [
                for (final e in const [(0, 'Today'), (1, 'Tomorrow'), (3, 'In 3 days')])
                  ChoiceChip(label: Text(e.$2), selected: _arriveDays == e.$1, onSelected: (_) => setState(() => _arriveDays = e.$1)),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger))),
              const SizedBox(height: AppTheme.s4),
              GlassButton(label: 'Tell the warehouse', icon: Icons.check_rounded, onPressed: _save),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- desk side

/// The warehouse desk: check deposits in, see stock by room, watch the
/// temperatures.
class WarehouseDeskScreen extends ConsumerStatefulWidget {
  const WarehouseDeskScreen({super.key});

  @override
  ConsumerState<WarehouseDeskScreen> createState() => _WarehouseDeskState();
}

class _WarehouseDeskState extends ConsumerState<WarehouseDeskScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final w = ref.read(warehouseProvider.notifier);
      if (ref.read(marketProvider).demoMode) {
        await w.seedDemoIfEmpty();
        await w.simulateSensors();
        _timer = Timer.periodic(const Duration(seconds: 30), (_) => w.simulateSensors());
      }
      await w.writeOffExpired();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    final demo = ref.watch(marketProvider.select((s) => s.demoMode));
    final hub = 'Durban hub';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text('Warehouse: $hub', style: AppTheme.title2)),
              ]),
              TabBar(
                tabs: [
                  Tab(text: 'Receiving ${wh.expected.length}'),
                  Tab(text: 'Stock ${wh.stored.length}'),
                  const Tab(text: 'Rooms'),
                ],
              ),
              Expanded(
                child: TabBarView(children: [
                  _Receiving(wh, now, demo),
                  _Stock(wh, now),
                  _Rooms(wh, hub, demo),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The panels of the warehouse desk, so the back office website can lay them
/// out its own way.
class ReceivingPanel extends ConsumerWidget {
  const ReceivingPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Receiving(
      ref.watch(warehouseProvider), ref.watch(warehouseClockProvider)(), ref.watch(marketProvider.select((s) => s.demoMode)));
}

class StockPanel extends ConsumerWidget {
  const StockPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _Stock(ref.watch(warehouseProvider), ref.watch(warehouseClockProvider)());
}

class RoomsPanel extends ConsumerWidget {
  final String hub;
  const RoomsPanel({super.key, this.hub = 'Durban hub'});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _Rooms(ref.watch(warehouseProvider), hub, ref.watch(marketProvider.select((s) => s.demoMode)));
}

class _Receiving extends ConsumerWidget {
  final WarehouseState wh;
  final DateTime now;
  final bool demo;
  const _Receiving(this.wh, this.now, this.demo);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = wh.lots.where((l) => l.status == LotStatus.rejected).take(3).toList();
    return ListView(padding: const EdgeInsets.all(AppTheme.s5), children: [
      Text('Check deposits in at the door: weigh, take the temperature, then accept or turn away.', style: AppTheme.callout),
      const SizedBox(height: AppTheme.s3),
      if (wh.expected.isEmpty)
        GlassCard(child: Text('No deposits are expected right now.', style: AppTheme.callout))
      else
        for (final l in wh.expected) Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: _CheckIn(l, now)),
      if (recent.isNotEmpty) ...[
        const SectionTitle('⛔', 'Turned away'),
        for (final l in recent) Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: LotTagCard(l, now: now)),
      ],
    ]);
  }
}

class _CheckIn extends ConsumerStatefulWidget {
  final StockLot lot;
  final DateTime now;
  const _CheckIn(this.lot, this.now);

  @override
  ConsumerState<_CheckIn> createState() => _CheckInState();
}

class _CheckInState extends ConsumerState<_CheckIn> {
  late final _qty = TextEditingController(text: _q(widget.lot.qty));
  late final _temp = TextEditingController();
  String? _msg;
  bool _bad = false;

  @override
  void dispose() {
    _qty.dispose();
    _temp.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final q = double.tryParse(_qty.text.replaceAll(',', '.'));
    final t = double.tryParse(_temp.text.replaceAll(',', '.'));
    if (q == null || t == null) return setState(() {
      _msg = 'Enter the weight and the temperature.';
      _bad = true;
    });
    final r = await ref.read(warehouseProvider.notifier).receive(widget.lot.id, qty: q, tempC: t);
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {
      _msg = r;
      _bad = r != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lot;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.productName, style: AppTheme.headline),
        Text('${l.farmName}  -  announced ${_q(l.qty)} ${l.unit}', style: AppTheme.footnote),
        Text('${l.zone.label}, must arrive ${l.zone.band}. Use by ${_d(l.useBy)}', style: AppTheme.caption),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(child: _num(_qty, 'Weight (${l.unit})')),
          const SizedBox(width: AppTheme.s2),
          Expanded(child: _num(_temp, 'Temp (C)')),
        ]),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s2),
            child: Text(_msg!, style: AppTheme.footnote.copyWith(color: _bad ? AppTheme.danger : AppTheme.ok)),
          ),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(child: GlassButton(label: 'Check in', icon: Icons.qr_code_2_rounded, onPressed: _go)),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: GhostButton(
              label: 'Turn away',
              icon: Icons.block_rounded,
              onPressed: () => ref.read(warehouseProvider.notifier).reject(l.id, 'Turned away at the door by staff'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: AppTheme.body,
        decoration: InputDecoration(
          labelText: trn(label),
          filled: true,
          fillColor: AppTheme.glassFill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
        ),
      );
}

class _Stock extends StatelessWidget {
  final WarehouseState wh;
  final DateTime now;
  const _Stock(this.wh, this.now);

  @override
  Widget build(BuildContext context) {
    final byZone = <StorageZone, List<StockLot>>{};
    for (final l in wh.stored) {
      byZone.putIfAbsent(l.zone, () => []).add(l);
    }
    for (final v in byZone.values) {
      v.sort((a, b) => a.useBy.compareTo(b.useBy)); // first expiry first out
    }
    return ListView(padding: const EdgeInsets.all(AppTheme.s5), children: [
      Text('Goods that expire first are picked first.', style: AppTheme.callout),
      if (byZone.isEmpty)
        Padding(padding: const EdgeInsets.only(top: AppTheme.s3), child: GlassCard(child: Text('Nothing is in storage.', style: AppTheme.callout))),
      for (final z in StorageZone.values)
        if (byZone[z] != null) ...[
          SectionTitle('🧊', '${z.label} (${z.band})'),
          for (final l in byZone[z]!)
            Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: LotTagCard(l, now: now, atRisk: wh.zoneAtRisk(l.hub, l.zone))),
        ],
    ]);
  }
}

class _Rooms extends ConsumerWidget {
  final WarehouseState wh;
  final String hub;
  final bool demo;
  const _Rooms(this.wh, this.hub, this.demo);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(warehouseProvider.notifier);
    return ListView(padding: const EdgeInsets.all(AppTheme.s5), children: [
      Text('Every room has a temperature band. A reading outside it raises an alarm and holds that room\'s goods back from orders.', style: AppTheme.callout),
      if (demo)
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.s3),
          child: GlassCard(
            tint: AppTheme.warn.withValues(alpha: 0.12),
            child: Text('Demo: these sensor readings are simulated. A real warehouse would feed them from probes on each room.', style: AppTheme.footnote),
          ),
        ),
      const SizedBox(height: AppTheme.s3),
      for (final z in StorageZone.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s3),
          child: Builder(builder: (context) {
            final r = wh.latest(hub, z);
            final risk = wh.zoneAtRisk(hub, z);
            return GlassCard(
              tint: risk ? AppTheme.danger.withValues(alpha: 0.14) : null,
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(z.label, style: AppTheme.headline)),
                  Text(r == null ? '-' : '${r.c.toStringAsFixed(1)} C',
                      style: AppTheme.title3.copyWith(color: risk ? AppTheme.danger : _zoneColor(z))),
                ]),
                Text(
                    risk
                        ? 'Out of range. Must be ${z.band}. Goods in this room are held back until it recovers.'
                        : 'Band ${z.band}${r == null ? ', no reading yet' : ', last reading ${_t(r.at)}${r.manual ? ' (typed in)' : ''}'}',
                    style: AppTheme.footnote.copyWith(color: risk ? AppTheme.danger : null)),
                const SizedBox(height: AppTheme.s2),
                Row(children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Log in range',
                      icon: Icons.thermostat_rounded,
                      onPressed: () => store.logTemp(hub, z, double.parse(((z.minC + z.maxC) / 2).toStringAsFixed(1))),
                    ),
                  ),
                  if (demo) ...[
                    const SizedBox(width: AppTheme.s2),
                    Expanded(
                      child: GhostButton(
                        label: 'Door left open',
                        icon: Icons.sensor_door_rounded,
                        onPressed: () => store.logTemp(hub, z, z.maxC + 6, manual: false),
                      ),
                    ),
                  ],
                ]),
              ]),
            );
          }),
        ),
    ]);
  }
}
