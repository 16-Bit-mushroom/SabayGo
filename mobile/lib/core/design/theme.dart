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
    // Light, and the title sits left.
    //
    // The bar used to be a solid block of brand purple on every screen. Two
    // problems. It spent the loudest colour in the palette on the least
    // important row on the screen, which leaves nothing in reserve for the
    // thing the passenger actually came to do — a page where everything is
    // emphasised has no emphasis. And it forced white chrome, so a status
    // chip or an SOS icon in the bar had to be re-coloured to survive.
    //
    // Purple is now spent where it means something: the primary action, the
    // welcome screen, the rail on a journey. The bar recedes.
    //
    // A centred title is a phone-sized convention that stops working the
    // moment there is a back arrow on one side and an action on the other,
    // because the title shifts as actions come and go. Left-aligned, it
    // starts on the same gutter as the content beneath it.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceRaised,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpacing.gutter,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700,
        letterSpacing: -0.2, color: AppColors.textPrimary,
      ),
    ),

    // The inner tab bars (booking history, the conductor's manifest). The
    // indicator was the old 3.11:1 green; an indicator is the only thing
    // saying which tab is current, so it is held to 1.4.11's 3:1 and
    // reinforced by the label's own colour and weight.
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.divider,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
    // ── navigation ────────────────────────────────────────────────────
    // Selected state is carried three ways at once: the pill behind the
    // icon, the icon filling in, and the label going dark and heavier.
    // WCAG 1.4.1 rules out doing it by colour alone, and on a cheap screen
    // in sunlight a tinted pill is the first of the three to disappear.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      indicatorColor: AppColors.primaryContainer,
      elevation: 0,
      height: 68,
      // Labels always. Five unlabelled icons ask the passenger to learn an
      // icon language before they can book a van, and "what does the
      // envelope do" is not a question a first-time user should have.
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
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
    ),
  );
}

OutlineInputBorder _fieldBorder(Color c, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: c, width: width),
    );
