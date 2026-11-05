import 'package:flutter/material.dart';

/// "Gece mesaisi" design tokens. DESIGN.md is the human-readable source; this file is
/// the only place colors are defined. Screens read them through [FlowColors.of].
@immutable
class FlowColors extends ThemeExtension<FlowColors> {
  const FlowColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.lime,
    required this.onLime,
    required this.limeEdge,
    required this.accentText,
    required this.accentSoft,
    required this.teal,
    required this.tealText,
    required this.tealSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.info,
    required this.infoSoft,
    required this.dot,
    required this.ring,
    required this.meter,
  });

  final Brightness brightness;

  /// Page background.
  final Color canvas;

  /// Cards and panels.
  final Color surface;

  /// Selected rows, customer bubbles, tracks.
  final Color raised;

  /// The sidebar (always ink, even in light mode).
  final Color sunken;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color muted;
  final Color faint;

  /// The one accent: primary fills, the live dot, focus.
  final Color lime;

  /// Text and icons on [lime]; always ink.
  final Color onLime;

  /// Outline drawn around lime fills (ink in light mode, none in dark).
  final Color limeEdge;

  /// Accent used as text or icon color (lime in dark, olive in light).
  final Color accentText;
  final Color accentSoft;

  /// The assistant and the bot.
  final Color teal;
  final Color tealText;
  final Color tealSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final Color info;
  final Color infoSoft;

  /// Dot-grid motif.
  final Color dot;

  /// Signal-ring motif.
  final Color ring;

  /// Progress and usage bars.
  final Color meter;

  bool get isDark => brightness == Brightness.dark;

  static const dark = FlowColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF0E1116),
    surface: Color(0xFF161B22),
    raised: Color(0xFF1C232D),
    sunken: Color(0xFF0A0D12),
    border: Color(0xFF262E3A),
    borderStrong: Color(0xFF3A4452),
    text: Color(0xFFF4F6F8),
    muted: Color(0xFF9AA4B2),
    faint: Color(0xFF8692A2),
    lime: Color(0xFFC6F432),
    onLime: Color(0xFF0E1116),
    limeEdge: Color(0x00000000),
    accentText: Color(0xFFC6F432),
    accentSoft: Color(0x1FC6F432),
    teal: Color(0xFF2DD4BF),
    tealText: Color(0xFF2DD4BF),
    tealSoft: Color(0x1F2DD4BF),
    danger: Color(0xFFFF6B5B),
    dangerSoft: Color(0x24FF6B5B),
    warning: Color(0xFFF5B841),
    warningSoft: Color(0x24F5B841),
    info: Color(0xFF7CB7FF),
    infoSoft: Color(0x247CB7FF),
    dot: Color(0xFF262E3A),
    ring: Color(0x47C6F432),
    meter: Color(0xFFC6F432),
  );

  static const light = FlowColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F5F0),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFECEEE7),
    sunken: Color(0xFF0A0D12),
    border: Color(0xFFDDE1D6),
    borderStrong: Color(0xFFC5CABC),
    text: Color(0xFF0E1116),
    muted: Color(0xFF4A5361),
    faint: Color(0xFF5F6874),
    lime: Color(0xFFC6F432),
    onLime: Color(0xFF0E1116),
    limeEdge: Color(0xFF0E1116),
    accentText: Color(0xFF3F6212),
    accentSoft: Color(0x61C6F432),
    teal: Color(0xFF0F766E),
    tealText: Color(0xFF0F766E),
    tealSoft: Color(0x1A0F766E),
    danger: Color(0xFFB03A0A),
    dangerSoft: Color(0x1AB03A0A),
    warning: Color(0xFF8C5A00),
    warningSoft: Color(0x1F8C5A00),
    info: Color(0xFF1D4ED8),
    infoSoft: Color(0x1A1D4ED8),
    dot: Color(0xFFCDD3C4),
    ring: Color(0x4D3F6212),
    meter: Color(0xFF3F6212),
  );

  /// Tokens for the current theme. Falls back to the default palette for the theme's
  /// brightness, so widgets also render inside a plain `MaterialApp` (widget tests).
  static FlowColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FlowColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  FlowColors copyWith({Color? canvas, Color? surface, Color? text}) => FlowColors(
        brightness: brightness,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        raised: raised,
        sunken: sunken,
        border: border,
        borderStrong: borderStrong,
        text: text ?? this.text,
        muted: muted,
        faint: faint,
        lime: lime,
        onLime: onLime,
        limeEdge: limeEdge,
        accentText: accentText,
        accentSoft: accentSoft,
        teal: teal,
        tealText: tealText,
        tealSoft: tealSoft,
        danger: danger,
        dangerSoft: dangerSoft,
        warning: warning,
        warningSoft: warningSoft,
        info: info,
        infoSoft: infoSoft,
        dot: dot,
        ring: ring,
        meter: meter,
      );

  @override
  FlowColors lerp(ThemeExtension<FlowColors>? other, double t) {
    if (other is! FlowColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return FlowColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      sunken: c(sunken, other.sunken),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      lime: c(lime, other.lime),
      onLime: c(onLime, other.onLime),
      limeEdge: c(limeEdge, other.limeEdge),
      accentText: c(accentText, other.accentText),
      accentSoft: c(accentSoft, other.accentSoft),
      teal: c(teal, other.teal),
      tealText: c(tealText, other.tealText),
      tealSoft: c(tealSoft, other.tealSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      dot: c(dot, other.dot),
      ring: c(ring, other.ring),
      meter: c(meter, other.meter),
    );
  }
}

/// Fixed ink shades of the sidebar, which stays dark in both themes.
abstract final class FlowInk {
  static const line = Color(0xFF1F2630);
  static const panel = Color(0xFF12161D);
  static const selected = Color(0xFF1A2029);
}

/// Semantic tone of a badge, tile or notice.
enum FlowTone { accent, assistant, warning, info, danger, neutral }

extension FlowToneColors on FlowColors {
  Color toneText(FlowTone tone) => switch (tone) {
        FlowTone.accent => accentText,
        FlowTone.assistant => tealText,
        FlowTone.warning => warning,
        FlowTone.info => info,
        FlowTone.danger => danger,
        FlowTone.neutral => muted,
      };

  Color toneFill(FlowTone tone) => switch (tone) {
        FlowTone.accent => accentSoft,
        FlowTone.assistant => tealSoft,
        FlowTone.warning => warningSoft,
        FlowTone.info => infoSoft,
        FlowTone.danger => dangerSoft,
        FlowTone.neutral => const Color(0x00000000),
      };
}

/// Spacing scale (logical pixels).
abstract final class FlowSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page padding for a viewport width.
  static double pageGutter(double width) => width < 600 ? 16 : (width < 1100 ? 24 : 40);
}

/// Corner radii.
abstract final class FlowRadius {
  static const double control = 10;
  static const double card = 14;
  static const double panel = 18;
  static const double pill = 999;

  static BorderRadius get controlAll => BorderRadius.circular(control);
  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get panelAll => BorderRadius.circular(panel);
}

/// Motion durations; every animation honours `MediaQuery.disableAnimations`.
abstract final class FlowMotion {
  static const fast = Duration(milliseconds: 160);
  static const entrance = Duration(milliseconds: 240);
  static const stagger = Duration(milliseconds: 60);
  static const pulse = Duration(milliseconds: 2000);
  static const curve = Cubic(0.2, 0.7, 0.2, 1);

  /// True when the user asked for reduced motion. Repeating animations are also off
  /// under the widget-test binding, so `pumpAndSettle` can finish.
  static bool reduced(BuildContext context) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || WidgetsBinding.instance is! WidgetsFlutterBinding;
}

/// Layout breakpoints.
abstract final class FlowBreakpoints {
  /// Below this the shell uses the bottom navigation bar.
  static const double compact = 720;

  /// From this width the sidebar shows labels.
  static const double wide = 1100;
}
