import 'package:flutter/material.dart';

import 'tokens.dart';

/// The console's [ThemeData], dense enough for a desk, built from the one
/// light palette in `tokens.dart` (a monochromatic emerald on clean white).
///
/// What differs from `mobile/lib/core/design/theme.dart` is what a desktop
/// dashboard needs and a phone does not:
///
/// * **Buttons size to their label.** Mobile buttons use
///   `Size.fromHeight`, an infinite minimum width that fills a column on a
///   phone and throws inside a dialog's action row or a toolbar here.
/// * **Data tables** get a sunken header row and a divider between rows, so
///   a column of fares can be scanned without a grid of borders.
/// * **The sidebar** is forest green; the current entry is a lighter
///   green with its icon on a white plate tile (`operator_shell.dart`).
///
/// Two bundled families (10 Nov). **Inter** is the interface: body, labels,
/// tables and every amount, in tabular figures so a column of pesos lines
/// up. **Plus Jakarta Sans** carries the page titles, dialog titles and the
/// big figures on the cards: its rounder, geometric capitals give the page
/// a heading voice Inter does not have, and it too has tabular figures.
/// Both are bundled from `assets/fonts`, never fetched: a font that loads
/// from the network is missing on exactly the demo machine without it.
const _font = 'Inter';
const _display = 'PlusJakartaSans';

ThemeData buildConsoleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
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
  // Keyboard focus is a 2px ring outside the control, so it never reads
  // as a fill or a hover: forest on the page, ink around a green fill
  // (green on green would vanish). WCAG 2.4.7.
  WidgetStateProperty<BorderSide?> focusSide(Color ring, [BorderSide? rest]) =>
      WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
          ? BorderSide(color: ring, width: AppSizing.focusOutline, strokeAlign: BorderSide.strokeAlignOutside)
          : rest);

  return ThemeData(
    useMaterial3: true,
    fontFamily: _font,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    // Every InkWell answers the pointer with the same see-through emerald
    // (tokens.dart, "interaction"), not Material's grey.
    hoverColor: AppColors.hoverWash,
    focusColor: AppColors.focusWash,
    highlightColor: AppColors.pressWash,
    splashColor: AppColors.hoverWash,
    // Buttons look 40 high but take a 48px pointer target
    // (AppSizing.minTouchTarget); the web default shrink-wraps them.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // Material 3 tints raised surfaces with the primary. With a green
    // primary that turns every white card faintly green; panels stay white.
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

    // The parts of a page nobody draws still carry the palette: the caret,
    // selected text and the scrollbar.
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.22),
      selectionHandleColor: AppColors.primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged)
              ? AppColors.border
              : AppColors.disabled),
      radius: const Radius.circular(AppRadius.full),
      thickness: const WidgetStatePropertyAll(6),
    ),

    // ── type ──────────────────────────────────────────────────────────
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: _display, fontSize: 28, height: 1.25, fontWeight: FontWeight.w700,
        letterSpacing: -0.5, color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: _display, fontSize: 24, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.3, color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontFamily: _display, fontSize: 20, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.2, color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: _display, fontSize: 18, height: 1.35, fontWeight: FontWeight.w700,
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
        fontFamily: _font, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w600,
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
        fontFamily: _display, fontSize: 20, fontWeight: FontWeight.w700,
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
      labelStyle: TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600),
      // Medium against SemiBold, so the selected tab reads by weight as
      // well as colour. Inter is bundled at 400, 500, 600 and 700.
      unselectedLabelStyle:
          TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w500),
      // A tab under the pointer takes the wash in a rounded pill.
      overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed)
          ? AppColors.pressWash
          : (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? AppColors.hoverWash : null)),
      splashBorderRadius: BorderRadius.circular(AppRadius.sm),
    ),

    // ── actions ───────────────────────────────────────────────────────
    // The main action is the forest with white text (5.48:1); a step
    // darker under the pointer.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: AppColors.onAction,
        disabledForegroundColor: AppColors.disabled,
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(
        backgroundColor: _actionFill,
        side: focusSide(AppColors.textPrimary),
        // The main action rises under the pointer: a soft green lift.
        elevation: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? 0 : (s.contains(WidgetState.hovered) ? 3 : 0)),
        shadowColor: const WidgetStatePropertyAll(AppColors.liftShadow),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: AppColors.onAction,
        disabledForegroundColor: AppColors.disabled,
        elevation: 0,
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(backgroundColor: _actionFill),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(
        // Under the pointer the outline turns the reference's 059669.
        side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
            ? BorderSide(color: AppColors.primary, width: AppSizing.focusOutline, strokeAlign: BorderSide.strokeAlignOutside)
            : BorderSide(color: s.contains(WidgetState.hovered) ? AppColors.primaryLight : AppColors.border)),
        // ... and fills with the see-through wash.
        overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed)
            ? AppColors.pressWash
            : (s.contains(WidgetState.hovered) ? AppColors.hoverWash : null)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(48, 40),
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(
        side: focusSide(AppColors.primary),
        overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed)
            ? AppColors.pressWash
            : (s.contains(WidgetState.hovered) ? AppColors.hoverWash : null)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: focusSide(AppColors.primary)),
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
      // A field under the pointer takes the wash, like every other control.
      hoverColor: AppColors.hoverWash,
      isDense: true,
      // 14 + a 20 px line + 14: a text field is AppSizing.field (48) high,
      // level with every dropdown and picker box beside it.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: 14,
      ),
      border: _fieldBorder(AppColors.border),
      enabledBorder: _fieldBorder(AppColors.border),
      focusedBorder: _fieldBorder(AppColors.primary, width: AppSizing.focusOutline),
      errorBorder: _fieldBorder(AppColors.danger),
      focusedErrorBorder: _fieldBorder(AppColors.danger, width: AppSizing.focusOutline),
      disabledBorder: _fieldBorder(AppColors.disabled),
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
        fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600,
        letterSpacing: 0.4, color: AppColors.textMuted,
      ),
      dataTextStyle: TextStyle(
        fontFamily: _font, fontSize: 14, color: AppColors.textPrimary,
      ),
      dataRowColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered) ? AppColors.hoverWash : AppColors.surfaceRaised),
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
        fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w700,
        color: AppColors.onFill,
      ),
      // Focus rings like the buttons': ink around a selected (green) chip.
      side: WidgetStateBorderSide.resolveWith((s) => s.contains(WidgetState.focused)
          ? BorderSide(
              color: s.contains(WidgetState.selected) ? AppColors.textPrimary : AppColors.primary,
              width: AppSizing.focusOutline)
          : BorderSide(color: AppColors.divider)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
    ),
    dividerTheme: DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      barrierColor: AppColors.scrim,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: TextStyle(
        fontFamily: _display, fontSize: 18, fontWeight: FontWeight.w700,
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

final WidgetStateProperty<Color?> _actionFill = WidgetStateProperty.resolveWith((s) {
  if (s.contains(WidgetState.disabled)) return AppColors.surfaceSunken;
  if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) return AppColors.actionHover;
  return AppColors.action;
});
