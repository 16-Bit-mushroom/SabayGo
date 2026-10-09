import 'package:flutter/material.dart';

/// Design tokens for the coop_admin console.
///
/// **Two palettes, dark by default.** The console was redesigned in
/// October 2026 as an operations dashboard: near-black canvas, grey panels,
/// a light action colour, so the live map, the status colours and the
/// numbers carry the page. Light mode is the console's earlier palette
/// (ink on white, the SABAY GO owl's colours), kept for a bright office or
/// a washed-out projector. The person at the desk picks one with the
/// sun/moon button in the top bar ([Appearance]).
///
/// `mobile/` stays light and keeps its own tokens: a conductor reads it at
/// a van door in direct sunlight.
///
/// **Every pairing below is measured against WCAG 2.1 AA** in both
/// palettes (ratios are computed, not estimated). Three rules they keep:
///
/// 1. A status colour is legible as *text on any panel*, and anything
///    drawn *on* a filled colour -- a button, a badge, a pin -- uses
///    [AppPalette.onFill]: dark ink in the dark palette, white in the
///    light one.
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container` tint so a chip can state its meaning in
///    words, and callers include the label or an icon, not just the colour.
/// 3. Anything a pointer lands on is at least [AppSizing.minTouchTarget].
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.primaryLight,
    required this.primaryContainer,
    required this.onFill,
    required this.brand,
    required this.brandContainer,
    required this.logoPlate,
    required this.highlight,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.sidebar,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    required this.divider,
  });

  final Brightness brightness;

  /// The action colour: filled buttons, the selected menu entry, focus.
  /// The owl's ink -- near-white on the dark canvas, ink on white.
  final Color primary;

  /// Pressed / secondary action shade.
  final Color primaryLight;

  /// Neutral tint behind [primary] text (selected chip, avatar).
  final Color primaryContainer;

  /// Text and icons on any *filled* colour -- [primary], [highlight] and
  /// every status colour.
  final Color onFill;

  /// The logo's red: markers, route geometry, the SOS entry. Never a
  /// button fill, so a red SOS never sits beside a red "Save".
  final Color brand;
  final Color brandContainer;

  /// Behind the logo. The mark is black ink on transparent and is drawn
  /// only on a light surface, in both palettes.
  final Color logoPlate;

  /// The selected thing on the map: the chosen van, its route line, trip
  /// progress. One hue so the eye finds "what I clicked" at once.
  final Color highlight;

  /// Confirmed, paid, boarded, live.
  final Color success;
  final Color successContainer;

  /// Awaiting payment, a difference to look at.
  final Color warning;
  final Color warningContainer;

  /// Cancelled, failed, emergency.
  final Color danger;
  final Color dangerContainer;

  /// Informational, neither good nor bad: "At terminal", "Scheduled".
  final Color info;
  final Color infoContainer;

  /// The page canvas, behind every panel.
  final Color surface;

  /// Panels and cards -- where the data sits.
  final Color surfaceRaised;

  /// A step inside a panel: table headers, read-only fields, hover rows.
  final Color surfaceSunken;

  /// The sidebar and the top bar.
  final Color sidebar;

  final Color textPrimary;

  /// Secondary text is still text; "muted" is not licence to drop below AA.
  final Color textMuted;

  /// Boundary of an interactive control -- an input outline, a chip edge.
  /// Clears WCAG 1.4.11's 3:1 so a field has a perceivable edge.
  final Color border;

  /// Decorative separation only, where nothing must be located by it.
  final Color divider;

  /// Ratios against `surfaceRaised` (#17181C) unless stated.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFFECECF0), // 15.1:1; onFill on it 15.9:1
    primaryLight: Color(0xFFC9CAD2),
    primaryContainer: Color(0xFF2A2B31), // primary on it 12.0:1
    onFill: Color(0xFF111216), // lowest pairing, on danger: 6.8:1
    brand: Color(0xFFF0484F), // 4.85:1
    brandContainer: Color(0xFF3A1719),
    logoPlate: Color(0xFFECECF0),
    highlight: Color(0xFFC8F051), // 13.6:1
    success: Color(0xFF4ADE80), // 10.2:1; 8.2:1 on its container
    successContainer: Color(0xFF12301F),
    warning: Color(0xFFF5B841), // 10.0:1; 8.2:1 on its container
    warningContainer: Color(0xFF33270E),
    danger: Color(0xFFF87171), // 6.4:1; 5.8:1 on its container
    dangerContainer: Color(0xFF3A1719),
    info: Color(0xFF6AA9FA), // 7.3:1; 6.0:1 on its container
    infoContainer: Color(0xFF14294A),
    surface: Color(0xFF0E0F12),
    surfaceRaised: Color(0xFF17181C),
    surfaceSunken: Color(0xFF1F2025),
    sidebar: Color(0xFF131418),
    textPrimary: Color(0xFFF2F2F5), // 15.9:1
    textMuted: Color(0xFFA3A6B0), // 7.3:1; 6.7:1 on surfaceSunken
    border: Color(0xFF70737E), // 3.75:1; 3.44:1 on surfaceSunken
    divider: Color(0xFF2B2D33),
  );

  /// Ratios against white (`surfaceRaised`) unless stated. White text on
  /// every filled colour, the lowest being info at 5.75:1.
  static const light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF16161D), // 18.0:1
    primaryLight: Color(0xFF3A3A44),
    primaryContainer: Color(0xFFECECF0), // primary on it 15.3:1
    onFill: Color(0xFFFFFFFF),
    brand: Color(0xFFC8151D), // 5.86:1
    brandContainer: Color(0xFFFBE7E8),
    logoPlate: Color(0xFFFFFFFF),
    highlight: Color(0xFF4D7C0F), // 4.99:1
    success: Color(0xFF00713C), // 6.13:1; 5.12:1 on its container
    successContainer: Color(0xFFE0EEE8),
    warning: Color(0xFF8A5A00), // 5.93:1; 5.00:1 on its container
    warningContainer: Color(0xFFF1EBE0),
    danger: Color(0xFFB3261E), // 6.54:1; 5.37:1 on its container
    dangerContainer: Color(0xFFF6E5E4),
    info: Color(0xFF1565C0), // 5.75:1; 4.74:1 on its container
    infoContainer: Color(0xFFE3EAF2),
    surface: Color(0xFFF7F7FA),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF0F0F4),
    sidebar: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A1A2E), // 17.06:1
    textMuted: Color(0xFF5A5A6E), // 6.73:1; 5.92:1 on surfaceSunken
    border: Color(0xFF84849C), // 3.64:1; 3.21:1 on surfaceSunken
    divider: Color(0xFFDDDDE5),
  );
}

/// The palette in use. Read as `AppColors.textPrimary` everywhere.
///
/// Getters rather than constants, so the console can switch palettes at
/// run time; that is why colours cannot appear inside `const` widgets.
/// Only [Appearance] calls [use], and it then redraws every widget.
class AppColors {
  static AppPalette _p = AppPalette.dark;

  static AppPalette get palette => _p;
  static bool get isDark => _p.brightness == Brightness.dark;
  static void use(AppPalette p) => _p = p;

  static Color get primary => _p.primary;
  static Color get primaryLight => _p.primaryLight;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onFill => _p.onFill;
  static Color get brand => _p.brand;
  static Color get brandContainer => _p.brandContainer;
  static Color get logoPlate => _p.logoPlate;
  static Color get highlight => _p.highlight;
  static Color get success => _p.success;
  static Color get successContainer => _p.successContainer;
  static Color get warning => _p.warning;
  static Color get warningContainer => _p.warningContainer;
  static Color get danger => _p.danger;
  static Color get dangerContainer => _p.dangerContainer;
  static Color get info => _p.info;
  static Color get infoContainer => _p.infoContainer;
  static Color get surface => _p.surface;
  static Color get surfaceRaised => _p.surfaceRaised;
  static Color get surfaceSunken => _p.surfaceSunken;
  static Color get sidebar => _p.sidebar;
  static Color get textPrimary => _p.textPrimary;
  static Color get textMuted => _p.textMuted;
  static Color get border => _p.border;
  static Color get divider => _p.divider;
}

/// A 4-point spacing scale. Ad-hoc padding is the main reason interfaces
/// look approximately aligned rather than aligned.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double section = 40;

  /// Screen side gutter. One value, so no two screens disagree about where
  /// the page begins.
  static const double gutter = 16;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  /// Chips and avatars.
  static const double full = 999;
}

/// Sizes that exist for reachability rather than looks.
class AppSizing {
  /// WCAG 2.5.5, and Material's floor. Nothing tappable goes below this,
  /// including icon buttons that look smaller than their hit area.
  static const double minTouchTarget = 48;

  /// Primary actions. Carried over deliberately: a conductor works one
  /// handed at a van door, often with a phone in a case and a queue behind
  /// the passenger.
  static const double primaryActionHeight = 52;

  /// Focus and error outlines. Two pixels so the state is visible without
  /// relying on colour alone.
  static const double focusOutline = 2;
}

/// Short, and consistent. A field app should feel immediate; long
/// transitions read as lag when someone is holding up a queue.
///
/// Callers that animate must still honour `MediaQuery.disableAnimations`
/// for users who ask the platform to reduce motion.
class AppDuration {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 240);
}
