import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'market_models.dart';

import '../tr_text.dart' show Text;
String rand(num v, {int decimals = 0}) {
  final s = v.toStringAsFixed(decimals);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return 'R$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// Fades and slides a child up the first time it is built. Used inside lazy
/// lists, so each card animates in exactly as it scrolls into view.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 * (widget.index % 4)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 36 * (1 - curve.value)),
          child: Transform.scale(scale: 0.96 + 0.04 * curve.value, child: child),
        ),
      ),
      child: widget.child,
    );
  }
}

class CountUp extends StatelessWidget {
  final double value;
  final TextStyle style;
  final int decimals;
  final String prefix;
  const CountUp(this.value,
      {super.key, required this.style, this.decimals = 0, this.prefix = 'R'});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        prefix.isEmpty
            ? v.toStringAsFixed(decimals)
            : rand(v, decimals: decimals),
        style: style,
      ),
    );
  }
}

/// Header that scales, fades and drifts as the page scrolls under it.
class ParallaxHeader extends SliverPersistentHeaderDelegate {
  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? trailing;

  ParallaxHeader({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.trailing,
  });

  @override
  double get maxExtent => 190;
  @override
  double get minExtent => 92;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (t > 0.05) const GlassBar(),
        Positioned(
          right: -10 - 30 * t,
          top: 0 - 40 * t,
          child: Opacity(
            opacity: (0.32 - t * 0.5).clamp(0.0, 0.32),
            child: Transform.rotate(
              angle: t * 0.5,
              child: Text(emoji, style: const TextStyle(fontSize: 118)),
            ),
          ),
        ),
        Positioned(
          left: AppTheme.s6,
          right: AppTheme.s6,
          bottom: AppTheme.s4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: AppTheme.largeTitle.copyWith(
                            fontSize: 34 - 10 * t)),
                    Opacity(
                      opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                      child: Text(subtitle, style: AppTheme.callout),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant ParallaxHeader old) =>
      old.title != title || old.subtitle != subtitle || old.trailing != trailing;
}

class SectionTitle extends StatelessWidget {
  final String emoji;
  final String text;
  final Widget? trailing;
  const SectionTitle(this.emoji, this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, AppTheme.s6, 0, AppTheme.s3),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppTheme.s2),
            Expanded(child: Text(text, style: AppTheme.title3)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: AppTheme.caption.copyWith(color: color)),
        ]),
      );
}

/// Circular progress used for the resilience score and group buys.
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final Color color;
  final Widget center;
  const RingGauge(
      {super.key,
      required this.value,
      required this.size,
      required this.color,
      required this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, color),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppTheme.textPrimary.withValues(alpha: 0.1);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.color != color;
}

class AlertBanner extends StatefulWidget {
  final MarketAlert alert;
  final VoidCallback onTap;
  const AlertBanner({super.key, required this.alert, required this.onTap});

  @override
  State<AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<AlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          boxShadow: [
            BoxShadow(
              color: a.color.withValues(alpha: 0.10 + 0.22 * _pulse.value),
              blurRadius: 14 + 22 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: GlassCard(
        tint: a.color.withValues(alpha: 0.14),
        onTap: widget.onTap,
        child: Row(
          children: [
            Text(a.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: AppTheme.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: AppTheme.headline),
                  const SizedBox(height: 2),
                  Text(a.body, style: AppTheme.footnote),
                  const SizedBox(height: AppTheme.s3),
                  Wrap(
                    spacing: AppTheme.s2,
                    runSpacing: AppTheme.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pill(a.area, color: a.color, icon: Icons.place_rounded),
                      if (a.trust != null)
                        Pill(a.trust!, color: AppTheme.sprout, icon: Icons.verified_rounded),
                      Text('${a.cta} →',
                          style: AppTheme.footnote.copyWith(
                              color: a.color, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
