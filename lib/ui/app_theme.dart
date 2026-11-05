import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'tokens.dart';

/// Builds the light and dark themes from [FlowColors]. Every Material widget the app
/// uses is themed here so screens never restyle controls locally.
abstract final class FlowTheme {
  static ThemeData dark() => _build(FlowColors.dark);
  static ThemeData light() => _build(FlowColors.light);

  static ThemeData of(Brightness brightness) => brightness == Brightness.dark ? dark() : light();

  static ThemeData _build(FlowColors c) {
    final dark = c.isDark;
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: dark ? c.lime : c.accentText,
      onPrimary: dark ? c.onLime : const Color(0xFFFFFFFF),
      primaryContainer: dark ? const Color(0xFF242C19) : c.lime,
      onPrimaryContainer: dark ? c.lime : c.onLime,
      secondary: c.teal,
      onSecondary: dark ? c.onLime : const Color(0xFFFFFFFF),
      secondaryContainer: dark ? const Color(0xFF12282A) : const Color(0xFFDCEEEC),
      onSecondaryContainer: c.tealText,
      tertiary: c.warning,
      onTertiary: dark ? c.onLime : const Color(0xFFFFFFFF),
      tertiaryContainer: dark ? const Color(0xFF2E2716) : const Color(0xFFF3E9D6),
      onTertiaryContainer: c.warning,
      error: c.danger,
      onError: dark ? c.onLime : const Color(0xFFFFFFFF),
      errorContainer: dark ? const Color(0xFF34201F) : const Color(0xFFF6E4DC),
      onErrorContainer: c.danger,
      surface: c.canvas,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceDim: dark ? c.sunken : const Color(0xFFE7E9E2),
      surfaceBright: dark ? c.raised : c.surface,
      surfaceContainerLowest: dark ? c.sunken : c.surface,
      surfaceContainerLow: dark ? const Color(0xFF12161D) : const Color(0xFFF8F9F5),
      surfaceContainer: c.surface,
      surfaceContainerHigh: dark ? c.raised : const Color(0xFFF1F2EC),
      surfaceContainerHighest: dark ? const Color(0xFF232B36) : c.raised,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: c.text,
      onInverseSurface: c.canvas,
      inversePrimary: dark ? const Color(0xFF3F6212) : c.lime,
      surfaceTint: const Color(0x00000000),
    );
    final text = flowTextTheme(c);
    final controlShape = RoundedRectangleBorder(borderRadius: FlowRadius.controlAll);
    const controlSize = Size(64, 44);
    final limeSide = dark ? BorderSide.none : BorderSide(color: c.limeEdge);
    final focusColor = dark ? c.lime : c.accentText;

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: FlowRadius.controlAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      fontFamily: FlowFonts.text,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [c],
      splashFactory: InkRipple.splashFactory,
      hoverColor: c.text.withValues(alpha: 0.04),
      focusColor: c.lime.withValues(alpha: 0.18),
      highlightColor: const Color(0x00000000),
      dividerColor: c.border,
      disabledColor: c.faint,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0x00000000),
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        shape: Border(bottom: BorderSide(color: c.border)),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: const Color(0x00000000),
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadius.cardAll,
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(controlSize),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.raised : c.lime,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.onLime,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.onLime,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? BorderSide(color: c.border) : limeSide,
          ),
          overlayColor: WidgetStatePropertyAll(c.onLime.withValues(alpha: 0.08)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(controlSize),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStatePropertyAll(c.surface),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.text,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.text,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.disabled) ? c.border : c.borderStrong),
          ),
          overlayColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.06)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(controlSize),
          shape: WidgetStatePropertyAll(controlShape),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStatePropertyAll(c.raised),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.text,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.accentText,
          ),
          overlayColor: WidgetStatePropertyAll(c.accentText.withValues(alpha: 0.08)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: WidgetStatePropertyAll(controlShape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.faint : c.text,
          ),
          overlayColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.06)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.lime,
        foregroundColor: c.onLime,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: limeSide),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.canvas,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: inputBorder(c.borderStrong),
        enabledBorder: inputBorder(c.borderStrong),
        disabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(focusColor, 2),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger, 2),
        labelStyle: text.bodyMedium?.copyWith(color: c.muted),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: focusColor, fontWeight: FontWeight.w600),
        hintStyle: text.bodyMedium?.copyWith(color: c.faint),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: c.danger),
        prefixIconColor: c.faint,
        suffixIconColor: c.faint,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.raised),
          surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.raised),
          surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.raised,
        surfaceTintColor: const Color(0x00000000),
        elevation: dark ? 0 : 6,
        shadowColor: const Color(0x22000000),
        textStyle: text.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
      ),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return c.lime;
          if (s.contains(WidgetState.disabled)) return c.raised;
          return const Color(0x00000000);
        }),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(color: s.contains(WidgetState.selected) ? c.limeEdge : c.border),
        ),
        labelStyle: text.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? c.onLime : c.muted),
        ),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: c.onLime),
        checkmarkColor: c.onLime,
        iconTheme: IconThemeData(color: c.muted, size: 16),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        shape: const StadiumBorder(),
        showCheckmark: false,
        brightness: c.brightness,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        height: 72,
        indicatorColor: c.lime,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            color: s.contains(WidgetState.selected) ? c.text : c.muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.onLime : c.muted, size: 22),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.sunken,
        indicatorColor: c.lime,
        selectedIconTheme: IconThemeData(color: c.onLime),
        unselectedIconTheme: IconThemeData(color: c.muted),
        selectedLabelTextStyle: text.labelMedium,
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: c.muted),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: const Color(0x00000000),
        shape: const RoundedRectangleBorder(),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.text,
        unselectedLabelColor: c.muted,
        labelStyle: text.titleSmall?.copyWith(fontSize: 15),
        unselectedLabelStyle: text.titleSmall?.copyWith(fontSize: 15),
        indicatorColor: dark ? c.lime : c.text,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: c.border,
        overlayColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.04)),
        tabAlignment: TabAlignment.start,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 42)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          side: WidgetStatePropertyAll(BorderSide(color: c.border)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.raised : c.canvas,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.text : c.muted,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accentText : c.muted,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.muted,
        textColor: c.text,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: FlowTextStatic.mono(c),
        selectedColor: c.text,
        selectedTileColor: c.raised,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.controlAll),
        minVerticalPadding: 10,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: c.muted,
        collapsedIconColor: c.muted,
        textColor: c.text,
        collapsedTextColor: c.text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: const Color(0x00000000),
        elevation: dark ? 0 : 8,
        shadowColor: const Color(0x33000000),
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.panelAll, side: BorderSide(color: c.border)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: const Color(0x00000000),
        modalBackgroundColor: c.surface,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: c.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(FlowRadius.panel)),
          side: BorderSide(color: c.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? c.raised : c.text,
        contentTextStyle: text.bodyMedium?.copyWith(color: dark ? c.text : c.canvas),
        actionTextColor: c.lime,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadius.cardAll,
          side: BorderSide(color: dark ? c.borderStrong : c.text),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(8)),
        textStyle: text.labelMedium?.copyWith(color: c.canvas),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.meter,
        linearTrackColor: c.raised,
        circularTrackColor: const Color(0x00000000),
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(FlowRadius.pill),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return c.border;
          return s.contains(WidgetState.selected) ? c.onLime : c.faint;
        }),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.lime : c.raised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.limeEdge : c.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : const Color(0x00000000),
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(color: s.contains(WidgetState.selected) ? scheme.primary : c.borderStrong, width: 1.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : c.borderStrong,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.lime,
        textColor: c.onLime,
        textStyle: FlowTextStatic.mono(c).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.borderStrong),
        radius: const Radius.circular(FlowRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: focusColor,
        selectionColor: c.lime.withValues(alpha: 0.35),
        selectionHandleColor: focusColor,
      ),
      iconTheme: IconThemeData(color: c.muted, size: 20),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: const Color(0x00000000),
        headerBackgroundColor: c.raised,
        headerForegroundColor: c.text,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.panelAll),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.panelAll),
      ),
    );
  }
}

/// Mono text style without a BuildContext, for theme construction.
abstract final class FlowTextStatic {
  static TextStyle mono(FlowColors c) => TextStyle(
        fontFamily: FlowFonts.mono,
        fontFamilyFallback: FlowFonts.monoFallback,
        fontSize: 12,
        color: c.muted,
      );
}
