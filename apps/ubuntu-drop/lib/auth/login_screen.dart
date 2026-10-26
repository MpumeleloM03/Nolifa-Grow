import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'auth_service.dart';
import 'auth_user.dart';
import 'auth_widgets.dart';
import 'signup_screen.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Email and password sign-in, with a way over to sign-up.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
      () => ref.read(authServiceProvider).signIn(_email.text, _password.text),
    );
    problem == null
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = problem;
      });
    }
  }

  Future<void> _reset() async {
    if (checkEmail(_email.text) != null) {
      setState(
        () => _error = 'Type your email above, then tap Forgot password.',
      );
      return;
    }
    final problem = await attempt(
      () => ref.read(authServiceProvider).sendReset(_email.text),
    );
    if (!mounted) return;
    setState(() => _error = problem);
    if (problem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.leaf,
          content: Text(
            'If ${_email.text.trim()} has an account, a reset link is on its way.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(authServiceProvider).isLocal;
    return AuthFrame(
      children: [
        const AuthBrand(
          line: 'Food and water your community can count on, even when things go wrong.',
        ),
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
                Text('Welcome back', style: AppTheme.title2),
                const SizedBox(height: AppTheme.s3),
                const LanguagePicker(),
                const SizedBox(height: AppTheme.s5),
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
                  onSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password.' : null,
                ),
                if (!local)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _reset,
                      child: Text(
                        'Forgot password?',
                        style: AppTheme.footnote.copyWith(
                          color: AppTheme.sprout,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: AppTheme.s2),
                if (_error != null) ErrorNote(_error!),
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                  label: 'Sign in',
                  icon: Icons.arrow_forward_rounded,
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
            Text('New here?', style: AppTheme.subhead),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignupScreen()),
              ),
              child: Text(
                'Create an account',
                style: AppTheme.headline.copyWith(color: AppTheme.sprout),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
