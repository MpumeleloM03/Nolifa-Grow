import 'package:flutter/material.dart';

/// Design tokens for Nolifa Grow.
///
/// Type ramp and spacing follow the iOS Human Interface Guidelines so the app
/// reads as native on iPhone. Surfaces are translucent and layered rather than
/// flat cards, which is what gives the app its depth on the gradient backdrop.
class AppTheme {
  /// True while the light palette is active. Set by [AppearanceScope], which
  /// rebuilds the whole tree when it flips, so every getter below re-reads it.
  static bool isLight = false;
  static Brightness get brightness => isLight ? Brightness.light : Brightness.dark;
  static Color _p(Color dark, Color light) => isLight ? light : dark;

  // Brand
  static const Color forest = Color(0xFF1B4332);
  static const Color forestDeep = Color(0xFF0B1F17);

  /// Text and icons that sit on a solid accent fill (buttons, selected chips).
  static Color get onAccent => _p(const Color(0xFF07150F), Colors.white);

  /// Bottom sheets, dialogs and dropdown menus.
  static Color get sheet => _p(const Color(0xFF10291F), const Color(0xFFFFFFFF));

  /// Solid page colour on the older full-screen pages (About, History, Map).
  static Color get pageGreen => _p(const Color(0xFF1B4332), const Color(0xFFF5F7F5));

  /// Page background: deep forest in dark mode, soft off-white in light mode.
  static Color get surface => _p(forestDeep, const Color(0xFFF5F7F5));
  static const Color leaf = Color(0xFF2D6A4F);
  static Color get sprout => _p(const Color(0xFF52D1A4), const Color(0xFF178260));

  // Mode accents — plants read green, livestock reads warm.
  static Color get plantAccent => sprout;
  static Color get livestockAccent => _p(const Color(0xFFE8A33D), const Color(0xFFB9770E));

  // Status
  static Color get danger => _p(const Color(0xFFFF6B6B), const Color(0xFFD64545));
  static Color get warn => livestockAccent;
  static Color get ok => sprout;

  // Glass
  static const double blurSigma = 24;
  static Color get glassFill => _p(const Color(0x1AFFFFFF), const Color(0xA3FFFFFF));
  static Color get glassFillStrong => _p(const Color(0x24FFFFFF), const Color(0xCCFFFFFF));
  static Color get glassBorder => _p(const Color(0x2EFFFFFF), const Color(0x1F1B4332));
  static Color get glassBorderSoft => _p(const Color(0x14FFFFFF), const Color(0x141B4332));

  // Text
  static Color get textPrimary => _p(const Color(0xFFF5F7F5), const Color(0xFF0F2A1F));
  static Color get textSecondary => _p(const Color(0xB3F5F7F5), const Color(0xB30F2A1F));
  static Color get textTertiary => _p(const Color(0x80F5F7F5), const Color(0x800F2A1F));

  // Corner radii — generous, iOS-style continuous curves.
  static const double rCard = 28;
  static const double rControl = 18;
  static const double rChip = 12;

  // 4pt spacing scale.
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;

  /// The app's backdrop. Glass surfaces need something with tonal variation
  /// behind them, otherwise the blur has nothing to reveal and reads as flat grey.
  static LinearGradient get backdrop => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isLight
            ? const [Color(0xFFE9F3EE), Color(0xFFF5F7F5), Color(0xFFEAF2ED)]
            : const [Color(0xFF14352A), Color(0xFF0B1F17), Color(0xFF102A22)],
        stops: const [0.0, 0.55, 1.0],
      );

  /// iOS text styles. Tracking values approximate Apple's optical sizing —
  /// large text tightens, small text opens up.
  static TextStyle get largeTitle => TextStyle(
      fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.15, color: textPrimary);
  static TextStyle get title1 => TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.18, color: textPrimary);
  static TextStyle get title2 => TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2, color: textPrimary);
  static TextStyle get title3 => TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.25, color: textPrimary);
  static TextStyle get headline => TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3, color: textPrimary);
  static TextStyle get body => TextStyle(
      fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.2, height: 1.4, color: textPrimary);
  static TextStyle get callout => TextStyle(
      fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: -0.1, height: 1.4, color: textSecondary);
  static TextStyle get subhead => TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, height: 1.4, color: textSecondary);
  static TextStyle get footnote => TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, height: 1.35, color: textSecondary);
  static TextStyle get caption => TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1, height: 1.3, color: textTertiary);

  static ThemeData build() => _build(Brightness.dark);

  static ThemeData buildLight() => _build(Brightness.light);

  static ThemeData _build(Brightness mode) {
    final light = mode == Brightness.light;
    final bg = light ? const Color(0xFFF5F7F5) : forestDeep;
    final fg = light ? const Color(0xFF0F2A1F) : const Color(0xFFF5F7F5);
    final fgSoft = fg.withValues(alpha: 0.7);
    final fgFaint = fg.withValues(alpha: 0.5);
    final accent = light ? const Color(0xFF178260) : const Color(0xFF52D1A4);
    final scheme = ColorScheme.fromSeed(
      seedColor: leaf,
      brightness: mode,
    ).copyWith(
      surface: bg,
      primary: accent,
    );

    TextStyle t(double size, FontWeight w, double ls, double h, Color c) =>
        TextStyle(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c);

    return ThemeData(
      useMaterial3: true,
      brightness: mode,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: t(20, FontWeight.w600, -0.2, 1.25, fg),
        iconTheme: IconThemeData(color: fg),
      ),
      textTheme: TextTheme(
        displayLarge: t(34, FontWeight.w700, -0.6, 1.15, fg),
        headlineLarge: t(28, FontWeight.w700, -0.4, 1.18, fg),
        headlineMedium: t(22, FontWeight.w700, -0.3, 1.2, fg),
        headlineSmall: t(20, FontWeight.w600, -0.2, 1.25, fg),
        titleMedium: t(17, FontWeight.w600, -0.2, 1.3, fg),
        bodyLarge: t(17, FontWeight.w400, -0.2, 1.4, fg),
        bodyMedium: t(16, FontWeight.w400, -0.1, 1.4, fgSoft),
        bodySmall: t(13, FontWeight.w400, 0, 1.35, fgSoft),
        labelSmall: t(12, FontWeight.w500, 0.1, 1.3, fgFaint),
      ),
      dividerTheme: DividerThemeData(
          color: light ? const Color(0x141B4332) : const Color(0x14FFFFFF),
          thickness: 1,
          space: 1),
    );
  }
}
