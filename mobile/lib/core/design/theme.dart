import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's single [ThemeData].
///
/// Everything a screen can get from the theme, it should get from the theme.
///
/// **The office console's look** (10 Nov): the same VerdantPulse palette
/// ([AppColors]), the same type pair and the same component rules, sized
/// for a thumb rather than a mouse -- 52px main actions, 48px targets.
///
/// Type: **Inter** for text and **Plus Jakarta Sans** for headings and the
/// app bar title, bundled from `assets/fonts` (pubspec.yaml says why they
/// are carried rather than fetched).
///
/// [_font] is named on every style in this file, not only on [ThemeData].
/// A component theme's `TextStyle` replaces the ambient one rather than
/// merging with it, so a button label with no family declared falls through
/// to the engine default even when the app has a family set.
const _font = 'Inter';
const _display = 'PlusJakartaSans';

/// The main action: forest, a step darker while pressed, a sunken step
/// when it cannot be used. Text on it is white [AppColors.onAction].
final _actionFill = WidgetStateProperty.resolveWith<Color>((s) {
  if (s.contains(WidgetState.disabled)) return AppColors.surfaceSunken;
  if (s.contains(WidgetState.pressed) || s.contains(WidgetState.hovered)) {
    return AppColors.actionHover;
  }
  return AppColors.action;
});

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onFill,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.action,
    onSecondary: AppColors.onAction,
    secondaryContainer: AppColors.primaryContainer,
    onSecondaryContainer: AppColors.primary,
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

  const gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);
  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
  );
  const buttonLabel =
      TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    fontFamily: _font,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    splashFactory: InkSparkle.splashFactory,

    // ── type ──────────────────────────────────────────────────────────
    // Sizes are explicit rather than inherited so a screen cannot silently
    // land between two scale steps. Nothing is capped: text must survive
    // 200% scaling (WCAG 1.4.4), which is why headline sizes are restrained
    // and no single-line height is hardcoded in the widgets.
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: _display, fontSize: 28, height: 1.25, fontWeight: FontWeight.w800,
        letterSpacing: -0.5, color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: _display, fontSize: 22, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.3, color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: _display, fontSize: 18, height: 1.35, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: _font, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: _font, fontSize: 16, height: 1.5, color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: _font, fontSize: 14, height: 1.5, color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontFamily: _font, fontSize: 13, height: 1.45, color: AppColors.textMuted,
      ),
      labelLarge: TextStyle(
        fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600,
      ),
      // Micro-labels ("Boarding", "At terminal"). Tracking opened up a
      // little for the small size.
      labelSmall: TextStyle(
        fontFamily: _font, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w600,
        letterSpacing: 0.4, color: AppColors.textMuted,
      ),
    ),

    // ── chrome ────────────────────────────────────────────────────────
    // White, left-aligned, with the console's green rule beneath it: the
    // bar recedes and the loudest colour is kept for the one action that
    // matters on the screen. A centred title shifts as actions come and
    // go; left-aligned it starts on the same gutter as the content.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceRaised,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpacing.gutter,
      shape: Border(bottom: BorderSide(color: AppColors.edge)),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(
        fontFamily: _display, fontSize: 20, fontWeight: FontWeight.w700,
        letterSpacing: -0.2, color: AppColors.textPrimary,
      ),
    ),

    // The inner tab bars (booking history, the Dispatcher's manifest). An
    // indicator is the only thing saying which tab is current, so it is
    // held to 1.4.11's 3:1 and reinforced by the label's colour and weight.
    tabBarTheme: const TabBarThemeData(
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
    // The main action is the emerald with dark text, as on the console
    // (white on it would be 2.54:1); kelly while pressed.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: AppColors.onAction,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(backgroundColor: _actionFill),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: AppColors.onAction,
        disabledForegroundColor: AppColors.textMuted,
        elevation: 0,
        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(backgroundColor: _actionFill),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surfaceRaised,
        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
        shape: buttonShape,
        textStyle: buttonLabel,
      ).copyWith(
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.disabled)
                  ? AppColors.disabled
                  : s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)
                      ? AppColors.primaryLight
                      : AppColors.border,
              width: s.contains(WidgetState.focused) ? AppSizing.focusOutline : 1,
            )),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        // A text button is still a target, however small it looks.
        minimumSize: const Size(AppSizing.minTouchTarget,
            AppSizing.minTouchTarget),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSizing.minTouchTarget,
            AppSizing.minTouchTarget),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.action,
      foregroundColor: AppColors.onAction,
      elevation: 2,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600)),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceRaised),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.textPrimary),
        iconColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.textPrimary),
      ),
    ),

    // ── inputs ────────────────────────────────────────────────────────
    // The outline carries the control's boundary, so it uses the 3:1 border
    // rather than the decorative edge. Focus is two pixels of green -- a
    // visible change in weight, not only in hue.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg, vertical: AppSpacing.lg,
      ),
      border: _fieldBorder(AppColors.border),
      enabledBorder: _fieldBorder(AppColors.border),
      focusedBorder: _fieldBorder(AppColors.primary,
          width: AppSizing.focusOutline),
      errorBorder: _fieldBorder(AppColors.danger),
      focusedErrorBorder: _fieldBorder(AppColors.danger,
          width: AppSizing.focusOutline),
      labelStyle: const TextStyle(fontFamily: _font, color: AppColors.textMuted),
      floatingLabelStyle: const TextStyle(fontFamily: _font, color: AppColors.primary),
      hintStyle: const TextStyle(fontFamily: _font, color: AppColors.textMuted),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      // Errors must be readable, and must say what to do -- the copy is the
      // caller's job, the legibility is this file's.
      errorStyle: const TextStyle(
        fontFamily: _font, color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500,
      ),
    ),

    // ── containers ────────────────────────────────────────────────────
    // White cards with the console's mid-light green edge and no shadow:
    // the edge separates a card from the mist page, and a grey shadow
    // would muddy the green.
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.edge),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.primaryContainer,
      selectedColor: AppColors.primary,
      // Green on the soft tint at rest; white on the green fill when
      // selected (12 Nov). The label used to stay green on the green
      // fill -- 1:1, invisible -- and each screen had to override it.
      labelStyle: TextStyle(
        fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onFill : AppColors.primary),
      ),
      checkmarkColor: AppColors.onFill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.sm,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider, thickness: 1, space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.disabled,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        fontFamily: _display, fontSize: 20, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: gutter,
      minVerticalPadding: AppSpacing.md,
      iconColor: AppColors.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(fontFamily: _font, color: AppColors.onFill, fontSize: 14),
      actionTextColor: AppColors.edge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    // ── navigation ────────────────────────────────────────────────────
    // The console's selected sidebar entry, on a phone: an emerald pill
    // behind the icon, dark icon on it, the label green and heavier.
    // Selection is carried three ways at once because WCAG 1.4.1 rules out
    // colour alone, and on a cheap screen in sunlight a tint is the first
    // of the three to disappear.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.action,
      elevation: 0,
      height: 68,
      // Labels always. Five unlabelled icons ask the passenger to learn an
      // icon language before they can book a van.
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.onAction
                : AppColors.textMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          )),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primaryContainer,
    ),
  );
}

OutlineInputBorder _fieldBorder(Color c, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: c, width: width),
    );
