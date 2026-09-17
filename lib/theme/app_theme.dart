import 'package:flutter/material.dart';

/// Design tokens for Nolifa Grow.
///
/// Type ramp and spacing follow the iOS Human Interface Guidelines so the app
/// reads as native on iPhone. Surfaces are translucent and layered rather than
/// flat cards, which is what gives the app its depth on the gradient backdrop.
class AppTheme {
  // Brand
  static const Color forest = Color(0xFF1B4332);
  static const Color forestDeep = Color(0xFF0B1F17);
  static const Color leaf = Color(0xFF2D6A4F);
  static const Color sprout = Color(0xFF52D1A4);

  // Mode accents — plants read green, livestock reads warm.
  static const Color plantAccent = Color(0xFF52D1A4);
  static const Color livestockAccent = Color(0xFFE8A33D);

  // Status
  static const Color danger = Color(0xFFFF6B6B);
  static const Color warn = Color(0xFFE8A33D);
  static const Color ok = Color(0xFF52D1A4);

  // Glass
  static const double blurSigma = 24;
  static const Color glassFill = Color(0x1AFFFFFF);
  static const Color glassFillStrong = Color(0x24FFFFFF);
  static const Color glassBorder = Color(0x2EFFFFFF);
  static const Color glassBorderSoft = Color(0x14FFFFFF);

  // Text
  static const Color textPrimary = Color(0xFFF5F7F5);
  static const Color textSecondary = Color(0xB3F5F7F5);
  static const Color textTertiary = Color(0x80F5F7F5);

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
  static const LinearGradient backdrop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14352A), Color(0xFF0B1F17), Color(0xFF102A22)],
    stops: [0.0, 0.55, 1.0],
  );

  /// iOS text styles. Tracking values approximate Apple's optical sizing —
  /// large text tightens, small text opens up.
  static const TextStyle largeTitle = TextStyle(
      fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.15, color: textPrimary);
  static const TextStyle title1 = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.18, color: textPrimary);
  static const TextStyle title2 = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2, color: textPrimary);
  static const TextStyle title3 = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.25, color: textPrimary);
  static const TextStyle headline = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3, color: textPrimary);
  static const TextStyle body = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.2, height: 1.4, color: textPrimary);
  static const TextStyle callout = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: -0.1, height: 1.4, color: textSecondary);
  static const TextStyle subhead = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, height: 1.4, color: textSecondary);
  static const TextStyle footnote = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, height: 1.35, color: textSecondary);
  static const TextStyle caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.1, height: 1.3, color: textTertiary);

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: leaf,
      brightness: Brightness.dark,
    ).copyWith(
      surface: forestDeep,
      primary: sprout,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: forestDeep,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: title3,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      textTheme: const TextTheme(
        displayLarge: largeTitle,
        headlineLarge: title1,
        headlineMedium: title2,
        headlineSmall: title3,
        titleMedium: headline,
        bodyLarge: body,
        bodyMedium: callout,
        bodySmall: footnote,
        labelSmall: caption,
      ),
      dividerTheme: const DividerThemeData(color: glassBorderSoft, thickness: 1, space: 1),
    );
  }
}
