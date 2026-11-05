import 'package:flutter/material.dart';

import 'tokens.dart';

/// Bundled font families (see `assets/fonts/README.md`).
abstract final class FlowFonts {
  /// UI text, optical size 14.
  static const text = 'Bricolage';

  /// Headings, optical size 40, weights 700 and 800.
  static const display = 'BricolageDisplay';

  /// Numbers, times, prices, phone numbers and caps status labels.
  static const mono = 'JetBrainsMono';

  /// JetBrains Mono has no ₺; it falls back to Bricolage.
  static const monoFallback = [text];
}

/// The type scale. Weight extremes (400 against 800) and big jumps between numerals and
/// their labels carry the hierarchy.
TextTheme flowTextTheme(FlowColors c) {
  TextStyle display(double size, FontWeight weight, double tracking, {double height = 1.05}) => TextStyle(
        fontFamily: FlowFonts.display,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: height,
        color: c.text,
      );
  TextStyle text(double size, FontWeight weight, {double height = 1.45, Color? color, double tracking = 0}) =>
      TextStyle(
        fontFamily: FlowFonts.text,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color ?? c.text,
      );
  return TextTheme(
    displayLarge: display(56, FontWeight.w800, -2.4, height: 0.98),
    displayMedium: display(44, FontWeight.w800, -1.8, height: 1),
    displaySmall: display(36, FontWeight.w800, -1.3),
    headlineLarge: display(32, FontWeight.w800, -1.2),
    headlineMedium: display(28, FontWeight.w800, -0.9),
    headlineSmall: display(24, FontWeight.w700, -0.5, height: 1.15),
    titleLarge: display(20, FontWeight.w700, -0.3, height: 1.2),
    titleMedium: text(16, FontWeight.w600, height: 1.35),
    titleSmall: text(14, FontWeight.w600, height: 1.35),
    bodyLarge: text(16, FontWeight.w400, height: 1.5),
    bodyMedium: text(15, FontWeight.w400, height: 1.5),
    bodySmall: text(13, FontWeight.w400, height: 1.45, color: c.muted),
    labelLarge: text(15, FontWeight.w600, height: 1.2),
    labelMedium: text(13, FontWeight.w600, height: 1.2),
    labelSmall: text(12, FontWeight.w500, height: 1.2, color: c.muted),
  );
}

/// Mono styles that are not part of Material's [TextTheme].
abstract final class FlowText {
  /// Big numerals for KPIs and counters.
  static TextStyle number(BuildContext context, {double size = 40, Color? color}) => TextStyle(
        fontFamily: FlowFonts.mono,
        fontFamilyFallback: FlowFonts.monoFallback,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: -size * 0.045,
        height: 1,
        color: color ?? FlowColors.of(context).text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Times, prices and phone numbers inside text.
  static TextStyle mono(BuildContext context, {double size = 13, Color? color, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: FlowFonts.mono,
        fontFamilyFallback: FlowFonts.monoFallback,
        fontSize: size,
        fontWeight: weight,
        height: 1.35,
        color: color ?? FlowColors.of(context).muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small caps status labels: "CANLI", "TEMSİLCİ BEKLİYOR".
  static TextStyle caps(BuildContext context, {double size = 11, Color? color}) => TextStyle(
        fontFamily: FlowFonts.mono,
        fontFamilyFallback: FlowFonts.monoFallback,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * 0.12,
        height: 1.2,
        color: color ?? FlowColors.of(context).muted,
      );
}

/// Uppercases with Turkish rules (i → İ, ı → I), which `toUpperCase` gets wrong.
String upperTr(String value) => value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
