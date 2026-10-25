import 'package:ubuntu_core/ubuntu_core.dart' show confirmDeleteAccount;
import '../care/care_screen.dart';
import '../members/application_screen.dart';
import '../members/borehole_screen.dart';
import '../members/membership_screen.dart';
import '../members/vet_screens.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        AppearancePicker,
        BusinessScreen,
        FarmerWarehouseScreen,
        ProfileForm,
        Reveal,
        SectionTitle,
        TrustCenterScreen,
        WalletScreen;
import '../farm/farm_setup_screen.dart';
import '../impact/impact_screen.dart';
import '../screens/about_screen.dart';
import '../services/auth_service.dart';
import '../services/region_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../water/supplier_screen.dart';
import '../widgets/language_toggle.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
/// Personal details, the farm's store details, language, and the account.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  static const _types = [('plants', 'Crops'), ('livestock', 'Livestock'), ('both', 'Both')];
  late String _region = ref.read(currentUserProvider)?.region ?? '';
  late String _type = ref.read(currentUserProvider)?.farmType ?? 'both';

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final regions = [for (final r in RegionService.regions) r.name];
    final region = regions.contains(_region) ? _region : null;
    final farmer = user?.isFarmer ?? true;
    final driver = user?.isDriver ?? false;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(farmer ? 'Settings' : 'Me', style: AppTheme.largeTitle),
              Text(user?.email ?? '', style: AppTheme.callout),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            ProfileForm(
              farmer: farmer,
              extraFields: (changed) => [
                DropdownButtonFormField<String>(
                  initialValue: region,
                  isExpanded: true,
                  dropdownColor: AppTheme.sheet,
                  decoration: InputDecoration(
                      labelText: tr('Region'), prefixIcon: Icon(Icons.place_rounded, size: 20)),
                  items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) {
                    setState(() => _region = v ?? _region);
                    changed();
                  },
                ),
                if (farmer) Wrap(spacing: AppTheme.s2, children: [
                  for (final t in _types)
                    ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      onSelected: (_) {
                        setState(() => _type = t.$1);
                        changed();
                      },
                    ),
                ]),
              ],
              onSave: (saved) async {
                await ref.read(authServiceProvider).updateProfile(
                      name: saved.name.isEmpty ? (user?.name ?? '') : saved.name,
                      region: _region,
                      farmType: _type,
                    );
                ref.invalidate(authStateProvider);
              },
            ),
            if (farmer) ...[
            const SectionTitle('🩺', 'Membership and vets'),
            _Row(Icons.verified_rounded, 'Nolifa membership', 'Member R3 000 or Max R7 000 a month, 24 months',
                () => _push(const MembershipScreen())),
            _Row(Icons.videocam_rounded, 'Ask a vet', 'Send a video, get a diagnosis, chat with the vet',
                () => _push(const VetHomeScreen())),
            _Row(Icons.event_available_rounded, 'Herd care', 'Water, feed and vaccine reminders',
                () => _push(const CareScreen())),
            const SectionTitle('🚜', 'Farm'),
            _Row(Icons.agriculture_rounded, 'My farm', 'Size, soil, water sources and irrigation systems',
                () => _push(const FarmSetupScreen())),
            _Row(Icons.ac_unit_rounded, 'Nolifa warehouse', 'Deposit stock, see it tagged and cold-stored',
                () => _push(const FarmerWarehouseScreen())),
            const SectionTitle('🛒', 'Selling'),
            _Row(Icons.storefront_rounded, 'Sell on Nolifa Drop',
                'Registration, verification, plan and delivery', () => _push(const BusinessScreen())),
            _Row(Icons.assignment_ind_rounded, 'Farm application', 'ID, land, certificates and how you farm',
                () => _push(const FarmApplicationScreen())),
            _Row(Icons.water_drop_rounded, 'Water provider', 'Register as a supplier and help communities',
                () => _push(const WaterSupplierScreen())),
            _Row(Icons.water_rounded, 'Nolifa borehole', 'Call a trusted driller, member discount',
                () => _push(const BoreholeScreen())),
            ],
            _Row(Icons.account_balance_wallet_rounded, farmer || driver ? 'Wallet and payouts' : 'Wallet and receipts', null,
                () => _push(const WalletScreen())),
            if (farmer) ...[
              const SectionTitle('📈', 'Proof'),
              _Row(Icons.insights_rounded, 'Impact evidence', 'Accuracy, forecast checks and water saved, measured here',
                  () => _push(const ImpactScreen())),
            ],
            const SectionTitle('⚙️', 'App'),
            Reveal(
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                child: Row(children: [
                  Icon(Icons.translate_rounded, color: AppTheme.sprout),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(child: Text('Language', style: AppTheme.headline)),
                  const LanguageToggle(),
                ]),
              ),
            ),
            const SizedBox(height: AppTheme.s2),
            const AppearancePicker(),
            const SizedBox(height: AppTheme.s2),
            _Row(Icons.verified_user_rounded, 'Trust and safety', 'Escrow, disputes, demo or live mode',
                () => _push(const TrustCenterScreen())),
            _Row(Icons.info_outline_rounded, 'About Nolifa', null, () => _push(const AboutScreen())),
            const SizedBox(height: AppTheme.s2),
            _Row(Icons.logout_rounded, 'Sign out', null, () {
              HapticFeedback.mediumImpact();
              ref.read(authServiceProvider).signOut();
            }, color: AppTheme.danger),
            _Row(Icons.delete_forever_rounded, 'Delete my account', 'Removes your account, herd, photos and documents',
                () => confirmDeleteAccount(context, () => ref.read(authServiceProvider).deleteAccount()),
                color: AppTheme.danger),
          ]),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? note;
  final VoidCallback onTap;
  final Color? color;
  const _Row(this.icon, this.title, this.note, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s2),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
          onTap: onTap,
          child: Row(children: [
            Icon(icon, color: color ?? AppTheme.sprout),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppTheme.headline.copyWith(color: color)),
                if (note != null) Text(note!, style: AppTheme.caption),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
          ]),
        ),
      );
}
