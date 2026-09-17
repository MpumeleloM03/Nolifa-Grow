import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// The app-wide backdrop: a deep gradient with two soft colour wells.
///
/// Glass only reads as glass when there is something varied behind it to
/// refract, so these wells sit under every screen and give the blurred panels
/// their tonal shift.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const AppBackdrop({super.key, required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppTheme.sprout;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.backdrop),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: _Well(color: accent.withValues(alpha: 0.28), size: 340),
          ),
          Positioned(
            bottom: -180,
            left: -120,
            child: _Well(color: AppTheme.leaf.withValues(alpha: 0.34), size: 400),
          ),
          child,
        ],
      ),
    );
  }
}

class _Well extends StatelessWidget {
  final Color color;
  final double size;

  const _Well({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// A translucent, blurred panel.
///
/// The top-edge highlight is what separates this from a plain translucent box —
/// it mimics light catching the lip of a real pane of glass.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s5),
    this.radius = AppTheme.rCard,
    this.strong = false,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    final fill = tint ?? (strong ? AppTheme.glassFillStrong : AppTheme.glassFill);

    Widget panel = ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppTheme.blurSigma, sigmaY: AppTheme.blurSigma),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: border,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(const Color(0x14FFFFFF), fill),
                fill,
              ],
            ),
            border: Border.all(color: AppTheme.glassBorder, width: 1),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      panel = Material(
        color: Colors.transparent,
        borderRadius: border,
        child: InkWell(borderRadius: border, onTap: onTap, child: panel),
      );
    }
    return panel;
  }
}

/// Filled pill button for primary actions.
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? accent;
  final bool busy;
  final bool expand;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.accent,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.sprout;
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(AppTheme.rControl);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onPressed : null,
          child: Container(
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.s6, vertical: AppTheme.s4),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                colors: [color, Color.alphaBlend(const Color(0x33000000), color)],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF0B1F17)),
                  )
                else ...[
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: const Color(0xFF07150F)),
                    const SizedBox(width: AppTheme.s2),
                  ],
                  Text(
                    label,
                    style: AppTheme.headline.copyWith(color: const Color(0xFF07150F)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Low-emphasis action rendered as an outlined glass pill.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const GhostButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.rControl);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s5, vertical: AppTheme.s3),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: AppTheme.glassFill,
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: AppTheme.s2),
              ],
              Text(label, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text field styled to sit on glass.
class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? trailing;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;

  const GlassField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.trailing,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      style: AppTheme.body,
      cursorColor: AppTheme.sprout,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.subhead,
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textTertiary),
        suffixIcon: trailing,
        filled: true,
        fillColor: AppTheme.glassFill,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4, vertical: AppTheme.s4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          borderSide: const BorderSide(color: AppTheme.sprout, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          borderSide: const BorderSide(color: AppTheme.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          borderSide: const BorderSide(color: AppTheme.danger, width: 1.5),
        ),
      ),
    );
  }
}

/// Blurred scrim for a pinned nav bar.
///
/// A transparent pinned SliverAppBar lets scrolled content run straight through
/// the title. iOS obscures whatever passes underneath, so the bar needs its own
/// blurred backing rather than relying on the page backdrop.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: AppTheme.forestDeep.withValues(alpha: 0.6),
          alignment: Alignment.bottomCenter,
          child: Container(height: 1, color: AppTheme.glassBorderSoft),
        ),
      ),
    );
  }
}

/// Marks the app as running without a cloud backend.
///
/// Shown wherever a farmer might reasonably assume their data is reaching other
/// people. In local mode nothing leaves the phone, and implying otherwise would
/// be worse than the missing feature.
class LocalModeBadge extends StatelessWidget {
  final String detail;
  const LocalModeBadge({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.s3, vertical: AppTheme.s2),
      decoration: BoxDecoration(
        color: AppTheme.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.rChip),
        border: Border.all(color: AppTheme.warn.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_iphone_rounded, size: 14, color: AppTheme.warn),
          const SizedBox(width: AppTheme.s2),
          Flexible(
            child: Text(detail,
                style: AppTheme.caption.copyWith(color: AppTheme.warn)),
          ),
        ],
      ),
    );
  }
}
