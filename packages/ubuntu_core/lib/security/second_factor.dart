import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/resilient.dart';
import '../supabase/supabase_boot.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import '../tr_text.dart' show Text;
import '../tr.dart' show tr;
/// Wraps the signed-in part of an app. An account that holds a staff power
/// (admin, hub, vet, water provider, mediator, certifier) must prove the sign-in
/// with a 6-digit code emailed to it. Everyone else goes straight through.
///
/// The server enforces this; this screen is only how a person gets their code in.
/// If the check cannot be made (no signal), the child is shown and the server
/// still refuses anything privileged.
class SecondFactorGuard extends StatefulWidget {
  final Widget child;
  const SecondFactorGuard({super.key, required this.child});

  @override
  State<SecondFactorGuard> createState() => _SecondFactorGuardState();
}

class _SecondFactorGuardState extends State<SecondFactorGuard> {
  late Future<bool> _needed = _check();

  Future<bool> _check() async {
    if (!SupabaseBoot.ready || SupabaseBoot.client.auth.currentSession == null) return false;
    try {
      final r = await SupabaseBoot.client.rpc('second_factor_status');
      return r is Map && r['required'] == true && r['ok'] != true;
    } catch (e) {
      debugPrint('second factor: could not check: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _needed,
        builder: (context, snap) {
          if (snap.data == true) {
            return SecondFactorScreen(onVerified: () => setState(() => _needed = Future.value(false)));
          }
          return widget.child;
        },
      );
}

class SecondFactorScreen extends StatefulWidget {
  final VoidCallback onVerified;
  const SecondFactorScreen({super.key, required this.onVerified});

  @override
  State<SecondFactorScreen> createState() => _SecondFactorScreenState();
}

class _SecondFactorScreenState extends State<SecondFactorScreen> {
  final _code = TextEditingController();
  String? _sentTo;
  String? _message;
  bool _busy = false;
  int _wait = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  String _readable(Object e) {
    // The server writes its own plain sentences for these cases.
    if (e is PostgrestException && e.code == 'P0001') return e.message;
    return friendlyError(e, doing: 'do that');
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await SupabaseBoot.client.rpc('request_login_code');
      if (!mounted) return;
      if (r is Map && r['required'] == false) {
        widget.onVerified();
        return;
      }
      setState(() => _sentTo = r is Map ? r['sentTo'] as String? : null);
      _cooldown();
    } catch (e) {
      if (mounted) setState(() => _message = _readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cooldown() {
    _tick?.cancel();
    setState(() => _wait = 60);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _message = 'Enter the 6 digits from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await SupabaseBoot.client.rpc('verify_login_code', params: {'p_code': code});
      if (!mounted) return;
      if (ok == true) {
        widget.onVerified();
      } else {
        setState(() => _message = 'That code is not right, or it ran out. Check the email or ask for a new one.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = _readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.s6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: GlassCard(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Glyph('🔐', size: 36),
                      const SizedBox(height: AppTheme.s2),
                      Text('Check your email', style: AppTheme.title2),
                      const SizedBox(height: AppTheme.s2),
                      Text(
                          _sentTo == null
                              ? 'Your account can approve people and move money, so we confirm it is you. We are emailing you a 6-digit code.'
                              : 'We sent a 6-digit code to $_sentTo. It works for 10 minutes.',
                          style: AppTheme.callout),
                      const SizedBox(height: AppTheme.s4),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: AppTheme.title1.copyWith(letterSpacing: 8),
                        decoration: InputDecoration(counterText: '', hintText: tr('000000')),
                        onSubmitted: (_) => _verify(),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: AppTheme.s2),
                        Text(_message!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
                      ],
                      const SizedBox(height: AppTheme.s4),
                      GlassButton(label: 'Confirm', icon: Icons.verified_user_rounded, busy: _busy, onPressed: _verify),
                      const SizedBox(height: AppTheme.s2),
                      TextButton(
                        onPressed: _busy || _wait > 0 ? null : _send,
                        child: Text(_wait > 0 ? 'Send a new code in $_wait s' : 'Send a new code'),
                      ),
                      TextButton(
                        onPressed: () => SupabaseBoot.client.auth.signOut(),
                        child: const Text('Sign out'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
