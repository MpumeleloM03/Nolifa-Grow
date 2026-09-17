import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/region_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String _region = RegionService.regions.first.name;
  String _farmType = 'both';
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signUp(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            region: _region,
            farmType: _farmType,
          );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Create account'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Join your local\nfarming network',
                              style: AppTheme.title1),
                          const SizedBox(height: AppTheme.s2),
                          Text(
                            'Your region lets us warn you when disease is spreading nearby.',
                            style: AppTheme.callout,
                          ),
                          const SizedBox(height: AppTheme.s6),
                          GlassCard(
                            padding: const EdgeInsets.all(AppTheme.s6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GlassField(
                                  controller: _name,
                                  label: 'Full name',
                                  icon: Icons.person_outline_rounded,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) =>
                                      (v == null || v.trim().length < 2)
                                          ? 'Enter your name'
                                          : null,
                                ),
                                const SizedBox(height: AppTheme.s4),
                                GlassField(
                                  controller: _email,
                                  label: 'Email',
                                  icon: Icons.alternate_email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) =>
                                      (v == null || !v.contains('@'))
                                          ? 'Enter a valid email'
                                          : null,
                                ),
                                const SizedBox(height: AppTheme.s4),
                                GlassField(
                                  controller: _password,
                                  label: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _hide,
                                  validator: (v) => (v == null || v.length < 6)
                                      ? 'At least 6 characters'
                                      : null,
                                  trailing: IconButton(
                                    icon: Icon(
                                      _hide
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color: AppTheme.textTertiary,
                                    ),
                                    onPressed: () =>
                                        setState(() => _hide = !_hide),
                                  ),
                                ),
                                const SizedBox(height: AppTheme.s5),
                                Text('Your region', style: AppTheme.headline),
                                const SizedBox(height: AppTheme.s3),
                                _RegionPicker(
                                  value: _region,
                                  onChanged: (v) => setState(() => _region = v),
                                ),
                                const SizedBox(height: AppTheme.s5),
                                Text('What do you farm?',
                                    style: AppTheme.headline),
                                const SizedBox(height: AppTheme.s3),
                                _FarmTypePicker(
                                  value: _farmType,
                                  onChanged: (v) =>
                                      setState(() => _farmType = v),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: AppTheme.s3),
                                  Container(
                                    padding: const EdgeInsets.all(AppTheme.s3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger
                                          .withValues(alpha: 0.14),
                                      borderRadius:
                                          BorderRadius.circular(AppTheme.rChip),
                                      border: Border.all(
                                          color: AppTheme.danger
                                              .withValues(alpha: 0.4)),
                                    ),
                                    child: Text(_error!,
                                        style: AppTheme.footnote
                                            .copyWith(color: AppTheme.danger)),
                                  ),
                                ],
                                const SizedBox(height: AppTheme.s5),
                                GlassButton(
                                  label: 'Create account',
                                  icon: Icons.check_rounded,
                                  busy: _busy,
                                  onPressed: _submit,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _RegionPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.s2,
      runSpacing: AppTheme.s2,
      children: RegionService.regions.map((r) {
        final selected = r.name == value;
        return _Chip(
          label: r.name,
          selected: selected,
          onTap: () => onChanged(r.name),
        );
      }).toList(),
    );
  }
}

class _FarmTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _FarmTypePicker({required this.value, required this.onChanged});

  static const _options = {
    'plants': ('Crops', Icons.eco_rounded),
    'livestock': ('Livestock', Icons.pets_rounded),
    'both': ('Both', Icons.agriculture_rounded),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.entries.map((e) {
        final selected = e.key == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppTheme.s2),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: AppTheme.s4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.sprout.withValues(alpha: 0.18)
                      : AppTheme.glassFill,
                  borderRadius: BorderRadius.circular(AppTheme.rControl),
                  border: Border.all(
                    color: selected ? AppTheme.sprout : AppTheme.glassBorder,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(e.value.$2,
                        size: 22,
                        color: selected
                            ? AppTheme.sprout
                            : AppTheme.textSecondary),
                    const SizedBox(height: AppTheme.s1),
                    Text(e.value.$1,
                        style: AppTheme.footnote.copyWith(
                          color: selected
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4, vertical: AppTheme.s2),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.sprout.withValues(alpha: 0.18)
              : AppTheme.glassFill,
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(
            color: selected ? AppTheme.sprout : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.footnote.copyWith(
            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
