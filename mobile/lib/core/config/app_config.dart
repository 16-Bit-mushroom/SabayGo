import 'package:flutter/material.dart';

/// Build-time configuration.
///
/// The base URL is a `--dart-define` rather than a constant because the
/// same build has to reach three different hosts: an emulator sees the
/// host machine at 10.0.2.2, a physical handset needs the machine's LAN
/// address, and production needs a domain. Hardcoding any one of them
/// guarantees the other two break.
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.8:8000/api/v1',
  );

  /// Requests that hang forever look identical to a frozen app. Ten
  /// seconds is long enough for a slow terminal connection and short
  /// enough that a dead server surfaces as an error, not a spinner.
  static const Duration requestTimeout = Duration(seconds: 10);

  static const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
}

/// Brand palette, carried over from the existing screens.
class AppColors {
  static const Color primary = Color(0xFF2D2059);
  static const Color primaryLight = Color(0xFF463A78);
  static const Color accent = Color(0xFF00A859);
  static const Color danger = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFF9A825);
  static const Color surface = Color(0xFFF7F7FA);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textMuted = Color(0xFF6B6B80);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        // 52 is a comfortable touch target for a conductor working one
        // handed at a van door.
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDDDE5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDDDE5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
