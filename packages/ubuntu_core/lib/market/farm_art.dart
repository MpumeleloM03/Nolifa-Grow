import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../theme/app_theme.dart';

import '../tr_text.dart' show Text;
import 'package:ubuntu_core/theme/glyph.dart';
/// Tiles emoji across a banner at a slight tilt, so a card reads as what it
/// sells even before you read it. Deterministic: the same emojis always lay
/// out the same way.
class EmojiPattern extends StatelessWidget {
  final List<String> emojis;
  final double size;
  final double opacity;
  const EmojiPattern(this.emojis, {super.key, this.size = 30, this.opacity = 0.32});

  @override
  Widget build(BuildContext context) => emojis.isEmpty
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: CustomPaint(
              painter: _PatternPainter(emojis, size, opacity), size: Size.infinite));
}

class _PatternPainter extends CustomPainter {
  final List<String> emojis;
  final double size;
  final double opacity;
  _PatternPainter(this.emojis, this.size, this.opacity);

  @override
  void paint(Canvas canvas, Size area) {
    final step = size * 1.7;
    var i = 0;
    for (var row = 0, y = -size * 0.3; y < area.height + size; row++, y += step * 0.86) {
      final offset = row.isOdd ? step / 2 : 0.0;
      for (var x = -size + offset; x < area.width + size; x += step) {
        final e = emojis[(i + row) % emojis.length];
        i++;
        final icon = Glyph.lookup(e).$1;
        final tp = TextPainter(
          text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(fontSize: size, fontFamily: icon.fontFamily, package: icon.fontPackage, color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x + tp.width / 2, y + tp.height / 2);
        canvas.rotate(((i * 37) % 21 - 10) * math.pi / 180);
        canvas.saveLayer(
            Rect.fromLTWH(-tp.width, -tp.height, tp.width * 2, tp.height * 2),
            Paint()..color = Colors.white.withValues(alpha: opacity));
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.emojis != emojis || old.size != size || old.opacity != opacity;
}

/// Photos made for the demo farms, keyed by farm name. Farms that join later
/// have none and fall back to the drawn badge and the emoji pattern.
const _farmSlugs = <String, String>{
  'Mkhize Family Farm': 'mkhize',
  'Sithole Growers': 'sithole',
  'Dlamini Mill': 'dlamini',
  'Khumalo Poultry': 'khumalo',
  'Naidoo Orchards': 'naidoo',
  'Zulu Co-op': 'zulu',
  'Nolifa Depot': 'depot',
  // A real seller: the butchery's own logo and a photo of its team.
  'Fatboy Butcheries': 'fatboy',
};

ImageProvider? farmBanner(String name) => _farmSlugs[name] == null
    ? null
    : AssetImage('assets/farms/banner_${_farmSlugs[name]}.jpg', package: 'ubuntu_core');

ImageProvider? farmLogoImage(String name) => _farmSlugs[name] == null
    ? null
    : AssetImage('assets/farms/logo_${_farmSlugs[name]}.png', package: 'ubuntu_core');

/// A promo card's photo: 'fresh', 'rescue' or 'outage'.
ImageProvider promoPhoto(String key) =>
    AssetImage('assets/farms/promo_$key.jpg', package: 'ubuntu_core');

/// Darkens the bottom and left of a photo so text on top stays readable.
class PhotoScrim extends StatelessWidget {
  const PhotoScrim({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xCC000000), Color(0x33000000)],
          ),
        ),
        child: SizedBox.expand(),
      );
}

const _logoColors = <List<Color>>[
  [Color(0xFF52D1A4), Color(0xFF1E7A5C)],
  [Color(0xFFE8A33D), Color(0xFF9A5A12)],
  [Color(0xFF5AB8F0), Color(0xFF1F5F8E)],
  [Color(0xFFE86F9A), Color(0xFF8E2B55)],
  [Color(0xFFB4D455), Color(0xFF5E7A16)],
  [Color(0xFFFF8A65), Color(0xFF9E3A22)],
];

int _hash(String s) => s.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);

String _monogram(String name) {
  final words = name.replaceAll(RegExp(r"['’]s\b"), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words.first[0] + words[1][0]).toUpperCase();
}

/// A badge for a farm: a shape and colours picked from its name, its
/// initials, and the thing it sells most.
class FarmLogo extends StatelessWidget {
  final String name;
  final String emoji;
  final double size;
  const FarmLogo({super.key, required this.name, required this.emoji, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final photo = farmLogoImage(name);
    if (photo != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
            image: DecorationImage(image: photo, fit: BoxFit.cover),
          ),
        ),
      );
    }
    final h = _hash(name);
    final colors = _logoColors[h % _logoColors.length];
    final shape = h ~/ 7 % 4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        CustomPaint(size: Size(size, size), painter: _LogoPainter(shape, colors)),
        Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.04),
            child: Text(_monogram(name),
                style: TextStyle(
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Colors.white,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black38)])),
          ),
        ),
        Positioned(
          right: -size * 0.08,
          top: -size * 0.1,
          child: Container(
            padding: EdgeInsets.all(size * 0.05),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24)),
            child: Glyph(emoji, size: size * 0.3, tile: false),
          ),
        ),
      ]),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final int shape;
  final List<Color> colors;
  _LogoPainter(this.shape, this.colors);

  Path _path(Size s) {
    final w = s.width, h = s.height;
    switch (shape) {
      case 0: // circle
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
      case 1: // hexagon
        final r = w / 2;
        return Path()
          ..addPolygon([
            for (var i = 0; i < 6; i++)
              Offset(r + r * math.cos(math.pi / 3 * i + math.pi / 6),
                  r + r * math.sin(math.pi / 3 * i + math.pi / 6))
          ], true);
      case 2: // shield
        return Path()
          ..moveTo(w * 0.5, 0)
          ..lineTo(w, h * 0.16)
          ..lineTo(w, h * 0.55)
          ..quadraticBezierTo(w, h * 0.85, w * 0.5, h)
          ..quadraticBezierTo(0, h * 0.85, 0, h * 0.55)
          ..lineTo(0, h * 0.16)
          ..close();
      default: // leaf
        return Path()
          ..moveTo(w * 0.5, 0)
          ..quadraticBezierTo(w * 1.05, h * 0.05, w, h * 0.55)
          ..quadraticBezierTo(w * 0.95, h, w * 0.45, h)
          ..quadraticBezierTo(0, h * 0.95, 0, h * 0.45)
          ..quadraticBezierTo(0, h * 0.05, w * 0.5, 0);
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    final path = _path(s);
    canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)
              .createShader(Offset.zero & s));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.shape != shape || old.colors != colors;
}
