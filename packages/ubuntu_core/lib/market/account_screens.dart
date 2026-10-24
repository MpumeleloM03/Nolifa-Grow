import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/appearance.dart';
import '../theme/glass.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'honesty.dart';
import 'market_widgets.dart';
import 'savings_screen.dart';
import 'shop_screens.dart';
import 'trust_screens.dart';

import '../tr_text.dart' show Text;
// ================================================================ MENU

/// An extra row for the menu, supplied by the app (for example "Sign out").
class MenuItem {
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  final Color? color;
  const MenuItem(this.icon, this.label, this.onTap, {this.detail, this.color});
}

void openDropMenu(BuildContext context, {List<MenuItem> extra = const []}) =>
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => DropMenuScreen(extra: extra)));

/// Everything a customer needs that is not shopping: orders, wallet, settings,
/// safety and help.
class DropMenuScreen extends ConsumerWidget {
  final List<MenuItem> extra;
  const DropMenuScreen({super.key, this.extra = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final active = s.myOrders.where((o) => o.status != OrderStatus.delivered).length;
    final market = ref.watch(marketNameProvider);
    final name = s.profile.name.isNotEmpty
        ? s.profile.name
        : (market == 'Neighbour' ? 'Your account' : market);
    return ScreenFrame(title: 'Menu', children: [
      GlassCard(
        onTap: () => go(const ProfileSettingsScreen()),
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.sprout.withValues(alpha: 0.2),
            child: Text(name.characters.first.toUpperCase(),
                style: AppTheme.title2.copyWith(color: AppTheme.sprout)),
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppTheme.headline),
              Text(
                  s.profile.address.isEmpty
                      ? 'Add your delivery address'
                      : '${s.profile.address}${s.profile.suburb.isEmpty ? '' : ', ${s.profile.suburb}'}',
                  style: AppTheme.footnote),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
      ),
      _MenuRow(Icons.receipt_long_rounded, 'My orders',
          detail: active == 0 ? null : '$active on the way',
          onTap: () => go(const OrdersScreen())),
      _MenuRow(Icons.account_balance_wallet_rounded, 'Wallet and receipts',
          onTap: () => go(const WalletScreen())),
      _MenuRow(Icons.savings_rounded, 'My savings',
          detail: 'Rescue deals, group buys and fees', onTap: () => go(const SavingsScreen())),
      _MenuRow(Icons.settings_rounded, 'Settings', onTap: () => go(const ProfileSettingsScreen())),
      _MenuRow(Icons.verified_user_rounded, 'Trust and safety',
          detail: 'Escrow, PINs, disputes', onTap: () => go(const TrustCenterScreen())),
      _MenuRow(Icons.help_outline_rounded, 'Help and support', onTap: () => go(const HelpScreen())),
      for (final m in extra)
        _MenuRow(m.icon, m.label, detail: m.detail, onTap: m.onTap, color: m.color),
    ]);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  final Color? color;
  const _MenuRow(this.icon, this.label, {required this.onTap, this.detail, this.color});

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: color ?? AppTheme.sprout),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTheme.headline.copyWith(color: color)),
              if (detail != null) Text(detail!, style: AppTheme.caption),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
      );
}

// ============================================================== ORDERS

/// A customer's orders: on the way first, then history.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(marketProvider.select((s) => s.myOrders));
    final open = orders.where((o) => o.status != OrderStatus.delivered).toList();
    final done = orders.where((o) => o.status == OrderStatus.delivered).toList();
    return ScreenFrame(title: 'My orders', children: [
      if (orders.isEmpty)
        GlassCard(
          child: Column(children: [
            const Text('🧺', style: TextStyle(fontSize: 40)),
            const SizedBox(height: AppTheme.s2),
            Text('No orders yet', style: AppTheme.headline),
            Text('Pick a farm on the Shop tab and your order shows up here.',
                textAlign: TextAlign.center, style: AppTheme.footnote),
          ]),
        ),
      if (open.isNotEmpty) Text('On the way', style: AppTheme.title3),
      for (final o in open) OrderTile(order: o),
      if (done.isNotEmpty) Text('Earlier', style: AppTheme.title3),
      for (final o in done) OrderTile(order: o),
    ]);
  }
}

// ============================================================ SETTINGS

/// Personal details. Farmers also see their store details.
class ProfileSettingsScreen extends ConsumerWidget {
  final bool farmer;

  /// Extra sections an app adds under the form (language, sign out).
  final List<Widget> footer;
  const ProfileSettingsScreen({super.key, this.farmer = false, this.footer = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ScreenFrame(title: 'Settings', children: [ProfileForm(farmer: farmer), const SizedBox(height: AppTheme.s4), const AppearancePicker(), ...footer]);
}

class ProfileForm extends ConsumerStatefulWidget {
  final bool farmer;

  /// Extra fields an app adds to the personal-details card (for example region).
  /// Call the callback they receive when one of them changes, so Save wakes up.
  final List<Widget> Function(VoidCallback markChanged)? extraFields;

  /// Runs before the details are saved, for app-level accounts.
  final Future<void> Function(ProfileSettings saved)? onSave;
  const ProfileForm({super.key, this.farmer = false, this.extraFields, this.onSave});

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  late final ProfileSettings _p0 = ref.read(marketProvider).profile;
  late final _name = TextEditingController(
      text: _p0.name.isNotEmpty
          ? _p0.name
          : (ref.read(marketNameProvider) == 'Neighbour' ? '' : ref.read(marketNameProvider)));
  late final _phone = TextEditingController(text: _p0.phone);
  late final _address = TextEditingController(text: _p0.address);
  late final _suburb = TextEditingController(text: _p0.suburb);
  late final _farm = TextEditingController(text: _p0.farmName);
  late final _about = TextEditingController(text: _p0.farmAbout);
  late bool _orders = _p0.notifyOrders;
  late bool _water = _p0.notifyWater;
  late bool _outbreaks = _p0.notifyOutbreaks;
  bool _saved = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _suburb, _farm, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    final cur = ref.read(marketProvider).profile;
    final next = cur.copyWith(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          suburb: _suburb.text.trim(),
          notifyOrders: _orders,
          notifyWater: _water,
          notifyOutbreaks: _outbreaks,
          farmName: widget.farmer ? _farm.text.trim() : cur.farmName,
          farmAbout: widget.farmer ? _about.text.trim() : cur.farmAbout,
        );
    ref.read(marketProvider.notifier).updateProfile(next);
    await widget.onSave?.call(next);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved ✅'), behavior: SnackBarBehavior.floating));
  }

  Widget _switch(String label, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppTheme.sprout,
        title: Text(label, style: AppTheme.body),
        subtitle: Text(sub, style: AppTheme.caption),
        value: v,
        onChanged: (x) => setState(() {
          _saved = false;
          on(x);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final gap = const SizedBox(height: AppTheme.s3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Personal details', style: AppTheme.title3),
          gap,
          GlassField(
              controller: _name,
              label: 'Full name',
              icon: Icons.person_rounded,
              onChanged: (_) => _saved = false),
          gap,
          GlassField(
              controller: _phone,
              label: 'Cell number',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone),
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s2),
            child: Builder(builder: (context) {
              final ok = ref.watch(marketProvider.select((m) => m.profile.phoneVerified)) &&
                  ref.read(marketProvider).profile.phone == _phone.text.trim();
              return GestureDetector(
                onTap: ok
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen())),
                child: Pill(ok ? 'Phone verified' : 'Verify your phone to vote on water',
                    color: ok ? AppTheme.sprout : AppTheme.warn,
                    icon: ok ? Icons.verified_rounded : Icons.shield_outlined),
              );
            }),
          ),
          gap,
          GlassField(
              controller: _address,
              label: widget.farmer ? 'Farm or pickup address' : 'Delivery address',
              icon: Icons.home_rounded),
          gap,
          GlassField(controller: _suburb, label: 'Suburb or town', icon: Icons.map_rounded),
          if (widget.extraFields != null)
            for (final w in widget.extraFields!(() => setState(() => _saved = false))) ...[gap, w],
        ]),
      ),
      const SizedBox(height: AppTheme.s4),
      if (widget.farmer) ...[
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your store', style: AppTheme.title3),
            gap,
            GlassField(
                controller: _farm, label: 'Farm name (shown in bold)', icon: Icons.agriculture_rounded),
            gap,
            GlassField(controller: _about, label: 'One line about your farm', icon: Icons.notes_rounded),
            Text('Delivery is set on the Business page.', style: AppTheme.caption),
          ]),
        ),
        const SizedBox(height: AppTheme.s4),
      ],
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Notifications', style: AppTheme.title3),
          _switch('Orders and payments', 'New orders, deliveries, payouts', _orders, (v) => _orders = v),
          _switch('Water alerts', 'Low reservoirs and truck updates', _water, (v) => _water = v),
          _switch('Outbreak alerts', 'Livestock and crop disease near you', _outbreaks,
              (v) => _outbreaks = v),
        ]),
      ),
      const SizedBox(height: AppTheme.s4),
      GlassButton(
          label: _saved ? 'Saved' : 'Save changes',
          icon: _saved ? Icons.check_rounded : Icons.save_rounded,
          onPressed: _saved ? null : _save),
    ]);
  }
}

// =========================================================== BUSINESS

/// How a farmer starts selling on Nolifa Drop: register, get verified, choose
/// a plan, and say how orders reach the customer.
/// Opens the driver application form. Nolifa Delivery supplies it.
final driverApplicationScreenProvider = Provider<Widget Function()?>((ref) => null);

/// Opens the farm application form. Nolifa Grow supplies it.
final farmApplicationScreenProvider = Provider<Widget Function()?>((ref) => null);

class BusinessScreen extends ConsumerStatefulWidget {
  const BusinessScreen({super.key});

  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends ConsumerState<BusinessScreen> {
  String _kind = 'individual';
  final _reg = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = ref.read(marketProvider).business;
    _kind = b.kind;
    _reg.text = b.regNumber;
  }

  @override
  void dispose() {
    _reg.dispose();
    super.dispose();
  }

  Widget _step(int n, String title, String sub, bool done, Widget? action) => GlassCard(
        tint: done ? AppTheme.sprout.withValues(alpha: 0.10) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: done ? AppTheme.sprout : AppTheme.glassFillStrong,
            child: done
                ? Icon(Icons.check_rounded, size: 18, color: AppTheme.onAccent)
                : Text('$n', style: AppTheme.subhead),
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.headline),
              Text(sub, style: AppTheme.footnote),
              if (action != null) ...[const SizedBox(height: AppTheme.s3), action],
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final b = s.business;
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final self = s.profile.delivery == DeliveryMode.self;

    return ScreenFrame(title: 'Sell on Nolifa Drop', children: [
      GlassCard(
        tint: (s.canSell ? AppTheme.sprout : AppTheme.warn).withValues(alpha: 0.12),
        child: Row(children: [
          Text(s.inspectionPassed ? '✅' : (s.canSell ? '🟡' : '🔒'), style: const TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  s.inspectionPassed
                      ? 'Your store is open'
                      : s.canSell
                          ? 'Selling with limits'
                          : b.inspection == InspectionStatus.failed
                              ? 'Inspection needs another look'
                              : 'Finish the steps to start selling',
                  style: AppTheme.headline),
              Text(
                  s.inspectionPassed
                      ? 'Inspected and approved. No limits.'
                      : s.canSell
                          ? 'Fresh produce up to ${rand(Inspection.provisionalCap)} while your inspection is arranged. ${s.provisionalDaysLeft} days left to complete it.'
                          : b.inspection == InspectionStatus.failed
                              ? 'Fix what the inspector noted and book again. Your listings are paused.'
                              : 'Nolifa Drop lists farms that are registered, verified, on a plan and have shown their land. Keeps buyers safe.',
                  style: AppTheme.footnote),
            ]),
          ),
        ]),
      ),
      if (ref.watch(sellerApprovalProvider) != null || ref.watch(farmApplicationScreenProvider) != null)
        _step(
          1,
          'Farm application',
          s.serverApproved == true
              ? 'Approved by Nolifa. Your identity, business, land and farm details are checked, and buyers see your farm profile.'
              : 'We check your ID, your business, where the farm is and how big, your certificates, and how you look after your animals and crops. Nolifa staff review it before you sell.',
          s.serverApproved == true,
          s.serverApproved == true || ref.watch(farmApplicationScreenProvider) == null
              ? null
              : GlassButton(
                  label: 'Open my application',
                  icon: Icons.assignment_ind_rounded,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ref.read(farmApplicationScreenProvider)!()))),
        )
      else ...[
      _step(
        1,
        'Register your business',
        b.registered
            ? 'Registered as ${b.kind}${b.regNumber.isEmpty ? '' : ' • ${b.regNumber}'}'
            : 'A farmer, a co-op or a company can sell. Registration number is optional for individuals.',
        b.registered,
        b.registered
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppTheme.s2, children: [
                  for (final k in const ['individual', 'cooperative', 'company'])
                    ChoiceChip(
                      label: Text(k),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ]),
                const SizedBox(height: AppTheme.s3),
                GlassField(
                    controller: _reg, label: 'Registration number (optional)', icon: Icons.badge_rounded),
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                    label: 'Register',
                    icon: Icons.how_to_reg_rounded,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      store.registerBusiness(kind: _kind, regNumber: _reg.text.trim());
                    }),
              ]),
      ),
      _step(
        2,
        'Get verified',
        s.farmVerified
            ? 'Identity and payout account checked. Buyers see your badge.'
            : '${s.farmKyc.length} of ${farmerSteps.length} checks done: ID, bank account for payouts, farm location.',
        s.farmVerified,
        s.farmVerified
            ? null
            : GlassButton(
                label: 'Verify my farm',
                icon: Icons.verified_user_rounded,
                onPressed: () => go(const VerifyScreen(role: KycRole.farmer))),
      ),
      ],
      _step(
        3,
        'Choose a plan',
        b.planPaid
            ? '${s.plan.label} plan • R${s.plan.price} a month • ${(s.plan.commission * 100).round()}% commission'
            : 'A monthly platform fee covers support and your store. Pick the one that fits your volume.',
        b.planPaid,
        GlassButton(
            label: b.planPaid ? 'Change plan' : 'See plans',
            icon: Icons.workspace_premium_rounded,
            onPressed: () => go(const PlansScreen())),
      ),
      _step(
        4,
        'Show your land and crops',
        b.evidenceDone
            ? 'Photos of your land, crop and water source are in. You can sell fresh produce now, with limits.'
            : 'Take geo-tagged photos of your field, your crop and your water source. Works offline and uploads later. This opens selling with limits straight away, no waiting for a visit.',
        b.evidenceDone,
        b.evidenceDone
            ? null
            : GlassButton(
                label: 'Add photos',
                icon: Icons.add_a_photo_rounded,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  store.submitLandEvidence();
                }),
      ),
      _InspectionCard(s),
      Text('How your orders are delivered', style: AppTheme.title3),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<DeliveryMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: DeliveryMode.platform, label: Text('🛵 Nolifa Delivery')),
              ButtonSegment(value: DeliveryMode.self, label: Text('🚜 I deliver')),
            ],
            selected: {s.profile.delivery},
            onSelectionChanged: (v) {
              HapticFeedback.selectionClick();
              store.updateProfile(s.profile.copyWith(delivery: v.first));
            },
          ),
          const SizedBox(height: AppTheme.s3),
          Text(
              self
                  ? 'You bring orders to the customer yourself. You keep the whole delivery fee you set, and the customer\'s PIN still releases your payment.'
                  : 'A verified Nolifa driver collects from your farm. Customers pay a delivery fee from R${Fees.baseDelivery.toStringAsFixed(0)}. The driver is paid for the trip, and Nolifa adds to the fee when it falls short.',
              style: AppTheme.footnote),
          if (self) ...[
            const SizedBox(height: AppTheme.s3),
            Row(children: [
              Expanded(child: Text('Your delivery fee', style: AppTheme.body)),
              IconButton(
                  onPressed: s.profile.deliveryFee <= 0
                      ? null
                      : () => store.updateProfile(
                          s.profile.copyWith(deliveryFee: s.profile.deliveryFee - 5)),
                  icon: const Icon(Icons.remove_circle_outline_rounded)),
              Text(s.profile.deliveryFee <= 0 ? 'Free' : rand(s.profile.deliveryFee),
                  style: AppTheme.headline),
              IconButton(
                  onPressed: s.profile.deliveryFee >= 100
                      ? null
                      : () => store.updateProfile(
                          s.profile.copyWith(deliveryFee: s.profile.deliveryFee + 5)),
                  icon: const Icon(Icons.add_circle_outline_rounded)),
            ]),
          ],
        ]),
      ),
      const FreeVsPaidCard(),
      Text('What it costs', style: AppTheme.title3),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _fee('Monthly platform fee', 'R${s.plan.price}', 'Includes support'),
          _fee('Commission per sale', '${(s.plan.commission * 100).round()}%', 'Only when you are paid'),
          _fee('Buyer service fee', '3%', 'Paid by the customer, not you'),
          _fee('Delivery', self ? 'Yours' : 'Customer pays', self ? 'You set the fee' : 'Driver paid per trip'),
        ]),
      ),
    ]);
  }

  Widget _fee(String a, String b, String c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a, style: AppTheme.body),
              Text(c, style: AppTheme.caption),
            ]),
          ),
          Text(b, style: AppTheme.headline.copyWith(color: AppTheme.sprout)),
        ]),
      );
}

// ================================================================ HELP

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const faq = [
      ('How does my money stay safe?',
          'You pay into escrow. The farm is paid only after you give the delivery PIN or the protection window ends.'),
      ('Something is wrong with my order',
          'Open the order and tap Report a problem within the protection window. A mediator reviews it and money stays frozen until then.'),
      ('Who delivers?',
          'Some farms deliver themselves. Others use Nolifa Delivery, where a verified neighbour collects it. The farm card shows which.'),
      ('What do the fees pay for?',
          'A small buyer service fee (3%, min R2, max R15) covers payments, escrow and support. Delivery goes to the driver.'),
    ];
    return ScreenFrame(title: 'Help and support', children: [
      for (final f in faq)
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.$1, style: AppTheme.headline),
            const SizedBox(height: 4),
            Text(f.$2, style: AppTheme.footnote),
          ]),
        ),
      GlassCard(
        child: Row(children: [
          Icon(Icons.support_agent_rounded, color: AppTheme.sprout),
          const SizedBox(width: AppTheme.s3),
          Expanded(
              child: Text('Still stuck? Support: help@nolifa.example (demo address). Weekdays 8 to 5.',
                  style: AppTheme.footnote)),
        ]),
      ),
    ]);
  }
}


/// The on-site check. Three routes so a rural farm is never stuck waiting for
/// a surveyor who cannot reach it.
class _InspectionCard extends ConsumerWidget {
  final MarketState s;
  const _InspectionCard(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(marketProvider.notifier);
    final b = s.business;
    final visit = b.visitOn == null ? null : DateTime.fromMillisecondsSinceEpoch(b.visitOn!);
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return GlassCard(
      tint: (b.inspection == InspectionStatus.passed ? AppTheme.sprout : null)?.withValues(alpha: 0.10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧑\u200d🌾', style: TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text('On-site inspection', style: AppTheme.headline)),
          Pill(
              switch (b.inspection) {
                InspectionStatus.none => 'Not booked',
                InspectionStatus.requested => 'Requested',
                InspectionStatus.scheduled => 'Booked',
                InspectionStatus.passed => 'Passed',
                InspectionStatus.failed => 'Not passed',
              },
              color: switch (b.inspection) {
                InspectionStatus.passed => AppTheme.sprout,
                InspectionStatus.failed => AppTheme.danger,
                InspectionStatus.none => AppTheme.textSecondary,
                _ => AppTheme.warn,
              }),
        ]),
        const SizedBox(height: AppTheme.s2),
        Text(
            'An inspector checks that the land, the way you grow and the water are safe for food. It lifts the limits and lets you list eggs, milk and processed goods.',
            style: AppTheme.footnote),
        if (b.inspection == InspectionStatus.none || b.inspection == InspectionStatus.failed) ...[
          const SizedBox(height: AppTheme.s3),
          for (final r in InspectionRoute.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.s2),
              child: GlassCard(
                radius: AppTheme.rControl,
                padding: const EdgeInsets.all(AppTheme.s3),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  store.requestInspection(r);
                },
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.label, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
                      Text('${r.blurb} Usually within ${r.waitDays} days.', style: AppTheme.caption),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                ]),
              ),
            ),
        ],
        if (b.inspection == InspectionStatus.scheduled || b.inspection == InspectionStatus.requested) ...[
          const SizedBox(height: AppTheme.s3),
          Text('${b.route.label}${visit == null ? '' : ', expected by ${date(visit)}'}',
              style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
          if (s.demoMode) ...[
            const SizedBox(height: AppTheme.s3),
            Row(children: [
              Expanded(
                child: GlassButton(
                    label: 'Demo: inspector passes',
                    icon: Icons.check_rounded,
                    onPressed: () => store.recordInspection(passed: true)),
              ),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                child: GhostButton(
                    label: 'Demo: not passed',
                    onPressed: () => store.recordInspection(passed: false)),
              ),
            ]),
          ],
        ],
      ]),
    );
  }
}


// ============================================================ PHONE CHECK

/// Checks a phone number with a one-time code. A verified number is what lets a
/// household vote on a water request, so one person cannot vote from many
/// accounts. Demo: the code is shown on screen. Production sends it by SMS and
/// allows one verified number per account.
class PhoneVerifyScreen extends ConsumerStatefulWidget {
  const PhoneVerifyScreen({super.key});

  static const demoCode = '4821';

  @override
  ConsumerState<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends ConsumerState<PhoneVerifyScreen> {
  late final _phone = TextEditingController(text: ref.read(marketProvider).profile.phone);
  final _code = TextEditingController();
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _validPhone => RegExp(r'^(\+27|0)\d{9}$').hasMatch(_phone.text.replaceAll(RegExp(r'\s'), ''));

  @override
  Widget build(BuildContext context) {
    final verified = ref.watch(marketProvider.select((s) => s.profile.phoneVerified));
    return ScreenFrame(title: 'Verify your phone', children: [
      Text(
          'A verified phone number lets you vote on a water request, so every vote is a real person. One number counts once.',
          style: AppTheme.callout),
      if (verified)
        GlassCard(
          tint: AppTheme.sprout.withValues(alpha: 0.12),
          child: Row(children: [
            const Text('✅', style: TextStyle(fontSize: 28)),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text('Your phone is verified. You can vote on water requests.', style: AppTheme.headline)),
          ]),
        )
      else ...[
        GlassField(
          controller: _phone,
          label: 'Cell number (0821234567)',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (!_sent)
          GlassButton(
            label: 'Send code',
            icon: Icons.sms_rounded,
            onPressed: !_validPhone
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    setState(() => _sent = true);
                  },
          )
        else ...[
          PrototypeNotice('Demo: no SMS is sent. Your code is ${PhoneVerifyScreen.demoCode}. In production it arrives by SMS.'),
          GlassField(
            controller: _code,
            label: '4-digit code',
            icon: Icons.pin_rounded,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null) Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.danger)),
          GlassButton(
            label: 'Verify',
            icon: Icons.verified_rounded,
            onPressed: () {
              if (_code.text.trim() == PhoneVerifyScreen.demoCode) {
                HapticFeedback.mediumImpact();
                ref.read(marketProvider.notifier).verifyPhone(_phone.text.replaceAll(RegExp(r'\s'), ''));
              } else {
                setState(() => _error = 'That code does not match');
              }
            },
          ),
        ],
      ],
    ]);
  }
}
