import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// A water blue for the middle card. The theme has no blue token.
const _waterTint = Color(0xFF5BC0EB);

class _Card {
  final String emoji;
  final String title;
  final String body;
  final Color tint;

  /// Small emoji that drift around the big one as you swipe.
  final List<String> orbit;
  const _Card(this.emoji, this.title, this.body, this.tint, this.orbit);
}

List<_Card> get _cards => [
  _Card(
    '🥬',
    'A community that stays fed',
    'Buy straight from farms near you. When disease, drought or an outage hits, local farms keep food moving. Your money waits in escrow until you confirm with a PIN.',
    AppTheme.sprout,
    ['🍅', '🥕', '🌽'],
  ),
  const _Card(
    '💧',
    'Water you can count on',
    'Get an alert before your supply runs low. Check your community\'s reservoir any time. If it gets bad, ask for water trucks together with your neighbours.',
    _waterTint,
    ['🚰', '🚚', '🪣'],
  ),
  _Card(
    '🛵',
    'Delivered to your door',
    'Some farms bring your order themselves. Others use a verified neighbour on Nolifa Delivery. Either way, the PIN you give at the door releases the payment.',
    AppTheme.livestockAccent,
    ['📦', '💸', '⭐'],
  ),
];

/// Where the pager is, as a fraction. Falls back to [index] before first layout.
double _pageOf(PageController c, int index) =>
    (c.hasClients && c.position.haveDimensions)
    ? (c.page ?? index.toDouble())
    : index.toDouble();

/// Three swipeable cards shown once after the first sign-in.
class OnboardingScreen extends StatefulWidget {
  /// Called when the person taps Skip or Let's go.
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _index == _cards.length - 1;

  void _next() {
    if (_last) {
      widget.onDone();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _cards[_index].tint),
        duration: const Duration(milliseconds: 500),
        builder: (_, tint, child) => AppBackdrop(tint: tint, child: child!),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _last
                        ? const SizedBox.shrink(key: ValueKey('no-skip'))
                        : Padding(
                            key: const ValueKey('skip'),
                            padding: const EdgeInsets.only(right: AppTheme.s3),
                            child: TextButton(
                              onPressed: widget.onDone,
                              child: Text(
                                'Skip',
                                style: AppTheme.subhead.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _cards.length,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = i);
                  },
                  itemBuilder: (_, i) => AnimatedBuilder(
                    animation: _controller,
                    builder: (_, _) => _CardPage(
                      card: _cards[i],
                      delta: i - _pageOf(_controller, _index),
                    ),
                  ),
                ),
              ),
              _Dots(
                controller: _controller,
                count: _cards.length,
                index: _index,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.s6,
                  AppTheme.s5,
                  AppTheme.s6,
                  AppTheme.s6,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: GlassButton(
                    key: ValueKey(_last),
                    label: _last ? 'Let\'s go' : 'Next',
                    icon: _last
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: _next,
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

/// One card. [delta] is how far it sits from the centre: 0 is in view, -1 is
/// one page to the left, 1 one page to the right.
class _CardPage extends StatelessWidget {
  final _Card card;
  final double delta;
  const _CardPage({required this.card, required this.delta});

  @override
  Widget build(BuildContext context) {
    final away = delta.abs().clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        final art = (box.maxHeight * 0.44).clamp(150.0, 250.0);
        // Scrolls only when big system text pushes the copy past the screen.
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The art slides a little faster than the words under it.
                Transform.translate(
                  offset: Offset(delta * 110, 0),
                  child: Opacity(
                    opacity: 1 - away,
                    child: Transform.scale(
                      scale: 1 - 0.2 * away,
                      child: _Art(card: card, size: art, delta: delta),
                    ),
                  ),
                ),
                SizedBox(height: art * 0.16),
                Opacity(
                  opacity: (1 - away * 1.3).clamp(0.0, 1.0),
                  child: Column(
                    children: [
                      Text(
                        card.title,
                        textAlign: TextAlign.center,
                        style: AppTheme.title1,
                      ),
                      const SizedBox(height: AppTheme.s3),
                      Text(
                        card.body,
                        textAlign: TextAlign.center,
                        style: AppTheme.callout,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Art extends StatelessWidget {
  final _Card card;
  final double size;
  final double delta;
  const _Art({required this.card, required this.size, required this.delta});

  @override
  Widget build(BuildContext context) {
    // Three spots around the disc, each drifting at its own pace.
    const spots = [
      Alignment(-0.95, -0.55),
      Alignment(0.95, -0.1),
      Alignment(-0.6, 0.95),
    ];
    const drift = [60.0, -80.0, 100.0];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size * 0.78,
            height: size * 0.78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  card.tint.withValues(alpha: 0.42),
                  card.tint.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: AppTheme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: card.tint.withValues(alpha: 0.3),
                  blurRadius: 60,
                ),
              ],
            ),
            child: Text(card.emoji, style: TextStyle(fontSize: size * 0.4)),
          ),
          for (var i = 0; i < card.orbit.length; i++)
            Align(
              alignment: spots[i],
              child: Transform.translate(
                offset: Offset(delta * drift[i], 0),
                child: Text(
                  card.orbit[i],
                  style: TextStyle(fontSize: size * 0.13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dots that stretch toward the page you are moving to.
class _Dots extends StatelessWidget {
  final PageController controller;
  final int count;
  final int index;
  const _Dots({
    required this.controller,
    required this.count,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) {
          final page = _pageOf(controller, index);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++)
                Builder(
                  builder: (_) {
                    final near = 1 - (page - i).abs().clamp(0.0, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8 + 22 * near,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Color.lerp(
                          AppTheme.glassBorder,
                          AppTheme.sprout,
                          near,
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
