import 'package:flutter/material.dart' hide Text;
import 'package:ubuntu_core/ubuntu_core.dart';

import 'auth_user.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
/// Runs a sign-in action. Returns the problem in plain words, or null on success.
Future<String?> attempt(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on AuthException catch (e) {
    return e.message;
  } catch (e) {
    debugPrint('auth: $e');
    return 'Something went wrong. Try again.';
  }
}

/// The page every sign-in screen sits on: backdrop, keyboard-safe scrolling,
/// content centred in a phone-width column, and each block easing in.
class AuthFrame extends StatelessWidget {
  final List<Widget> children;

  /// Shows a back arrow top-left when set.
  final VoidCallback? onBack;

  const AuthFrame({super.key, required this.children, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppTheme.s6,
                        onBack == null
                            ? AppTheme.s8
                            : AppTheme.s10 + AppTheme.s4,
                        AppTheme.s6,
                        AppTheme.s8,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < children.length; i++)
                                Reveal(index: i, child: children[i]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (onBack != null)
                Positioned(
                  top: AppTheme.s1,
                  left: AppTheme.s2,
                  child: IconButton(
                    tooltip: tr('Back'),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                    ),
                    onPressed: onBack,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo and one line on what the app is for.
class AuthBrand extends StatelessWidget {
  final String line;
  const AuthBrand({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BrandMark(),
        const SizedBox(height: AppTheme.s5),
        Text('Nolifa Drop', style: AppTheme.largeTitle),
        const SizedBox(height: AppTheme.s2),
        Text(line, style: AppTheme.callout),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.sprout.withValues(alpha: 0.55),
                  AppTheme.leaf.withValues(alpha: 0.35),
                ],
              ),
              border: Border.all(color: AppTheme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sprout.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Text('💧', style: TextStyle(fontSize: 34)),
          ),
          const Positioned(right: 0, top: 0, child: _MarkBadge('🥬')),
          const Positioned(right: 6, bottom: -4, child: _MarkBadge('🛵')),
        ],
      ),
    );
  }
}

class _MarkBadge extends StatelessWidget {
  final String emoji;
  const _MarkBadge(this.emoji);

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppTheme.surface,
      border: Border.all(color: AppTheme.glassBorder),
    ),
    child: Text(emoji, style: const TextStyle(fontSize: 15)),
  );
}

/// A password field with a show and hide toggle.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final void Function(String)? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    return GlassField(
      controller: widget.controller,
      label: widget.label,
      icon: Icons.lock_outline_rounded,
      obscure: _hide,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      validator: widget.validator,
      trailing: IconButton(
        tooltip: _hide ? 'Show password' : 'Hide password',
        icon: Icon(
          _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: AppTheme.textTertiary,
        ),
        onPressed: () => setState(() => _hide = !_hide),
      ),
    );
  }
}

/// A problem, in red, announced to screen readers.
class ErrorNote extends StatelessWidget {
  final String message;
  const ErrorNote(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: AppTheme.s2),
        padding: const EdgeInsets.all(AppTheme.s3),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 18,
            ),
            const SizedBox(width: AppTheme.s2),
            Expanded(
              child: Text(
                message,
                style: AppTheme.footnote.copyWith(color: AppTheme.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on sign-in screens while Supabase is not connected.
class LocalNotice extends StatelessWidget {
  const LocalNotice({super.key});

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: LocalModeBadge(detail: 'Local mode: accounts stay on this phone'),
  );
}
