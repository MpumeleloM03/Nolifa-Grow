import 'package:flutter/material.dart';
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

/// Personal details, the farm's store details, language, and the account.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  static const _types = [('plants', '🌿 Crops'), ('livestock', '🐄 Livestock'), ('both', '🌾 Both')];
  late String _region = ref.read(currentUserProvider)?.region ?? '';
  late String _type = ref.read(currentUserProvider)?.farmType ?? 'both';

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final regions = [for (final r in RegionService.regions) r.name];
    final region = regions.contains(_region) ? _region : null;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Settings', style: AppTheme.largeTitle),
              Text(user?.email ?? '', style: AppTheme.callout),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            ProfileForm(
              farmer: true,
              extraFields: (changed) => [
                DropdownButtonFormField<String>(
                  initialValue: region,
                  isExpanded: true,
                  dropdownColor: AppTheme.sheet,
                  decoration: const InputDecoration(
                      labelText: 'Region', prefixIcon: Icon(Icons.place_rounded, size: 20)),
                  items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) {
                    setState(() => _region = v ?? _region);
                    changed();
                  },
                ),
                Wrap(spacing: AppTheme.s2, children: [
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
            const SectionTitle('🚜', 'Farm'),
            _Row(Icons.agriculture_rounded, 'My farm', 'Size, soil, water sources and irrigation systems',
                () => _push(const FarmSetupScreen())),
            _Row(Icons.ac_unit_rounded, 'Nolifa warehouse', 'Deposit stock, see it tagged and cold-stored',
                () => _push(const FarmerWarehouseScreen())),
            const SectionTitle('🛒', 'Selling'),
            _Row(Icons.storefront_rounded, 'Sell on Nolifa Drop',
                'Registration, verification, plan and delivery', () => _push(const BusinessScreen())),
            _Row(Icons.water_drop_rounded, 'Water provider', 'Register as a supplier and help communities',
                () => _push(const WaterSupplierScreen())),
            _Row(Icons.account_balance_wallet_rounded, 'Wallet and payouts', null,
                () => _push(const WalletScreen())),
            const SectionTitle('📈', 'Proof'),
            _Row(Icons.insights_rounded, 'Impact evidence', 'Accuracy, forecast checks and water saved, measured here',
                () => _push(const ImpactScreen())),
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
            _Row(Icons.info_outline_rounded, 'About Nolifa Grow', null, () => _push(const AboutScreen())),
            const SizedBox(height: AppTheme.s2),
            _Row(Icons.logout_rounded, 'Sign out', null, () {
              HapticFeedback.mediumImpact();
              ref.read(authServiceProvider).signOut();
            }, color: AppTheme.danger),
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
