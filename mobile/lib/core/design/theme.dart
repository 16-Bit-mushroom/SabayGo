import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's single [ThemeData].
///
/// Everything a screen can get from the theme, it should get from the theme.
/// The sweep that follows this file removes 389 raw `Colors.*` and 43
/// hardcoded `Color(0x...)` uses from `lib/views` — they exist because there
/// was nowhere central to put a decision, so each screen made its own.
///
/// Typeface is the bundled Roboto, deliberately. `google_fonts` fetches at
/// first run, and this app is used in connectivity dead zones by design —
/// the conductor's manifest queues walk-ins offline. A font that arrives
/// over the network is a font that is missing exactly when it matters.
/// "Premium" here comes from weight, tracking, spacing and restraint.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.success,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.successContainer,
    onSecondaryContainer: AppColors.success,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.danger,
    surface: AppColors.surfaceRaised,
    onSurface: AppColors.textPrimary,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
  );

  const gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  return ThemeData(
    useMaterial3: true,
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
        fontSize: 28, height: 1.25, fontWeight: FontWeight.w700,
        letterSpacing: -0.5, color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: -0.3, color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18, height: 1.35, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16, height: 1.4, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16, height: 1.5, color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14, height: 1.5, color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 13, height: 1.45, color: AppColors.textMuted,
      ),
      // Uppercase micro-labels ("BOARDING", "AT TERMINAL"). Tracking opened
      // up, because capitals set tight are markedly harder to read.
      labelSmall: TextStyle(
        fontSize: 11, height: 1.3, fontWeight: FontWeight.w700,
        letterSpacing: 0.8, color: AppColors.textMuted,
      ),
    ),

    // ── chrome ────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
      ),
    ),

    // ── actions ───────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        // A text button is still a target, however small it looks.
        minimumSize: const Size(AppSizing.minTouchTarget,
            AppSizing.minTouchTarget),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSizing.minTouchTarget,
            AppSizing.minTouchTarget),
      ),
    ),

    // ── inputs ────────────────────────────────────────────────────────
    // The outline carries the control's boundary, so it uses the 3:1 border
    // rather than the decorative divider. Focus is two pixels of primary —
    // a visible change in weight, not only in hue.
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
      labelStyle: const TextStyle(color: AppColors.textMuted),
      // Errors must be readable, and must say what to do — the copy is the
      // caller's job, the legibility is this file's.
      errorStyle: const TextStyle(
        color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500,
      ),
    ),

    // ── containers ────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceRaised,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.divider),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.primaryContainer,
      labelStyle: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: gutter,
      minVerticalPadding: AppSpacing.md,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      indicatorColor: AppColors.primaryContainer,
      elevation: 0,
      height: 68,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
  );
}

OutlineInputBorder _fieldBorder(Color c, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: c, width: width),
    );
