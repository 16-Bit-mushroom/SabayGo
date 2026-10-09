import 'package:flutter/material.dart';

import 'tokens.dart';

/// The console's [ThemeData], dense enough for a desk, built from whichever
/// palette is in use (dark by default, light on request -- see
/// `tokens.dart` and `appearance.dart`). Called again on every switch.
///
/// What differs from `mobile/lib/core/design/theme.dart` is what a desktop
/// dashboard needs and a phone does not:
///
/// * **Buttons size to their label.** Mobile buttons use
///   `Size.fromHeight`, an infinite minimum width that fills a column on a
///   phone and throws inside a dialog's action row or a toolbar here.
/// * **Data tables** get a sunken header row and a divider between rows, so
///   a column of fares can be scanned without a grid of borders.
/// * **The sidebar** is a shade off the canvas with a light pill for the
///   current screen.
///
/// Typeface is Roboto, bundled from `assets/fonts` like the mobile app. On
/// Flutter Web nothing declared a family before, so the console rendered in
/// whatever the browser chose -- a different face on every demo machine.
const _font = 'Roboto';

ThemeData buildConsoleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: AppColors.palette.brightness,
    primary: AppColors.primary,
    onPrimary: AppColors.onFill,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.info,
    onSecondary: AppColors.onFill,
    secondaryContainer: AppColors.infoContainer,
    onSecondaryContainer: AppColors.info,
    error: AppColors.danger,
    onError: AppColors.onFill,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.danger,
    surface: AppColors.surfaceRaised,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textMuted,
    surfaceContainerLowest: AppColors.surfaceRaised,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceSunken,
    surfaceContainerHighest: AppColors.surfaceSunken,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
  );
  const buttonPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl, vertical: AppSpacing.md,
  );
  const buttonLabel =
      TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600);
  // 40 high, not mobile's 52: a mouse pointer is precise, and a toolbar of
  // 52px buttons pushes the table it controls below the fold.
  const buttonMin = Size(64, 40);

  return ThemeData(
    useMaterial3: true,
    fontFamily: _font,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    // Material 3 tints raised surfaces with the primary. With an ink
    // primary that turns every white card faintly grey; panels stay white.
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.divider),
      ),
    ),

    // ── type ──────────────────────────────────────────────────────────
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: _font, fontSize: 28, height: 1.25, fontWeight: FontWeight.w700,
        letterSpacing: -0.5, color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: _font, fontSize: 24, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.3, color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontFamily: _font, fontSize: 20, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.2, color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: _font, fontSize: 18, height: 1.35, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: _font, fontSize: 15, height: 1.4, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontFamily: _font, fontSize: 14, height: 1.4, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: _font, fontSize: 15, height: 1.5, color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: _font, fontSize: 14, height: 1.45, color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontFamily: _font, fontSize: 12.5, height: 1.4, color: AppColors.textMuted,
      ),
      labelLarge: TextStyle(
        fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
      // Uppercase micro-labels: table column heads, KPI captions.
      labelSmall: TextStyle(
        fontFamily: _font, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: 0.6, color: AppColors.textMuted,
      ),
    ),

    // ── chrome ────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceRaised,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _font, fontSize: 20, fontWeight: FontWeight.w700,
        letterSpacing: -0.2, color: AppColors.textPrimary,
      ),
      shape: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.divider,
      labelStyle: TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600),
    ),

    // ── actions ───────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onFill,
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonLabel,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onFill,
        elevation: 0,
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonLabel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: buttonMin,
        padding: buttonPadding,
        side: BorderSide(color: AppColors.border),
        shape: buttonShape,
        textStyle: buttonLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(48, 40),
        shape: buttonShape,
        textStyle: buttonLabel,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(buttonLabel),
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceRaised),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.textPrimary),
        iconColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.textPrimary),
      ),
    ),

    // ── inputs ────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.md,
      ),
      border: _fieldBorder(AppColors.border),
      enabledBorder: _fieldBorder(AppColors.border),
      focusedBorder: _fieldBorder(AppColors.primary, width: AppSizing.focusOutline),
      errorBorder: _fieldBorder(AppColors.danger),
      focusedErrorBorder: _fieldBorder(AppColors.danger, width: AppSizing.focusOutline),
      disabledBorder: _fieldBorder(AppColors.divider),
      labelStyle: TextStyle(fontFamily: _font, color: AppColors.textMuted),
      floatingLabelStyle: TextStyle(fontFamily: _font, color: AppColors.textPrimary),
      hintStyle: TextStyle(fontFamily: _font, color: AppColors.textMuted),
      helperStyle: TextStyle(fontFamily: _font, color: AppColors.textMuted, fontSize: 12),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      errorStyle: TextStyle(
        fontFamily: _font, color: AppColors.danger, fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    ),

    // ── data ──────────────────────────────────────────────────────────
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppColors.surfaceSunken),
      headingTextStyle: TextStyle(
        fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w700,
        letterSpacing: 0.4, color: AppColors.textMuted,
      ),
      dataTextStyle: TextStyle(
        fontFamily: _font, fontSize: 14, color: AppColors.textPrimary,
      ),
      dataRowColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered) ? AppColors.surfaceSunken : AppColors.surfaceRaised),
      dividerThickness: 1,
      horizontalMargin: AppSpacing.lg,
      columnSpacing: AppSpacing.xxl,
      headingRowHeight: 44,
    ),

    // ── containers ────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceSunken,
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.primary,
      checkmarkColor: AppColors.onFill,
      labelStyle: TextStyle(
        fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w600,
        color: AppColors.onFill,
      ),
      side: BorderSide(color: AppColors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
    ),
    dividerTheme: DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: TextStyle(
        fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      contentTextStyle: TextStyle(
        fontFamily: _font, fontSize: 14, height: 1.45, color: AppColors.textPrimary,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: AppColors.divider),
      ),
      textStyle: TextStyle(fontFamily: _font, fontSize: 14, color: AppColors.textPrimary),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceRaised),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: TextStyle(fontFamily: _font, fontSize: 12, color: AppColors.onFill),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: TextStyle(fontFamily: _font, color: AppColors.onFill, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      width: 480,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.textMuted,
      textColor: AppColors.textPrimary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent),
      side: BorderSide(color: AppColors.border, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceSunken),
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.border),
      trackOutlineColor: WidgetStatePropertyAll(AppColors.border),
    ),
  );
}

OutlineInputBorder _fieldBorder(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: c, width: width),
    );
