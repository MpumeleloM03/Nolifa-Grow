import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'auth_service.dart';
import 'auth_user.dart';
import 'auth_widgets.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Creates an account from a name, an email and a password.
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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await attempt(
      () => ref
          .read(authServiceProvider)
          .signUp(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          ),
    );
    problem == null
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
    });
    // The sign-in screen sits underneath. Clear this one so the app can move on.
    if (problem == null) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(authServiceProvider).isLocal;
    return AuthFrame(
      onBack: () => Navigator.pop(context),
      children: [
        const AuthBrand(line: 'Join your community. It takes a minute.'),
        if (local) ...[
          const SizedBox(height: AppTheme.s4),
          const LocalNotice(),
        ],
        const SizedBox(height: AppTheme.s8),
        GlassCard(
          padding: const EdgeInsets.all(AppTheme.s6),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create your account', style: AppTheme.title2),
                const SizedBox(height: AppTheme.s2),
                Text(
                  'Neighbours see your name on orders and deliveries. Your email stays private.',
                  style: AppTheme.footnote,
                ),
                const SizedBox(height: AppTheme.s5),
                GlassField(
                  controller: _name,
                  label: 'Your name',
                  icon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                  validator: checkName,
                ),
                const SizedBox(height: AppTheme.s4),
                GlassField(
                  controller: _email,
                  label: 'Email',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: checkEmail,
                ),
                const SizedBox(height: AppTheme.s4),
                PasswordField(
                  controller: _password,
                  label: 'Password (8+ characters)',
                  onSubmitted: (_) => _submit(),
                  validator: checkPassword,
                ),
                if (_error != null) ErrorNote(_error!),
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
        ),
        const SizedBox(height: AppTheme.s6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already a neighbour?', style: AppTheme.subhead),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Sign in',
                style: AppTheme.headline.copyWith(color: AppTheme.sprout),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
