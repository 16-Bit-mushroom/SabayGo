import 'package:flutter/material.dart';

/// Design tokens: the single place that owns colour, spacing, radius and
/// motion for the passenger and Dispatcher apps.
///
/// **The palette is the office console's** (10 Nov, VerdantPulse: balanced
/// mid-green), so a passenger, a Dispatcher and the Terminal Manager see
/// one product. Values and names match `operator_console/lib/core/design/
/// tokens.dart`; change one, change both.
///   F0FDF4 meadow mist      the page
///   FFFFFF / DCFCE7         cards; the soft emerald tint
///   86EFAC                  card edges, the app bar's rule
///   10B981 emerald          the main action, the selected tab
///   22C55E kelly            the main action pressed
///   047857                  green text and icons, focus, paid
///   1E3A2F slate green-grey the type
///
/// **Every pairing is measured against WCAG 2.1 AA** (computed, not
/// estimated). White text on the emerald is 2.54:1, so anything drawn on
/// the emerald or the kelly is [onAction], dark; green *text* is
/// [primary]. Three rules:
///
/// 1. A status colour is legible as *text on any card*, and anything drawn
///    *on* a dark filled colour uses [AppColors.onFill]; on the emerald,
///    [AppColors.onAction].
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container` tint so a chip states its meaning in words,
///    and callers include the label or an icon, not just the colour.
/// 3. Anything a finger lands on is at least [AppSizing.minTouchTarget].
///
/// A Dispatcher reads these at a van door in direct sunlight, which is why
/// the status colours are the deep ones and the tints carry them.
class AppRamp {
  static const Color n0 = Color(0xFFFFFFFF);
  static const Color n50 = Color(0xFFF0FDF4);
  static const Color n100 = Color(0xFFE8F7EE);
  static const Color n200 = Color(0xFFBBF7D0);
  static const Color n400 = Color(0xFFA3B8AD);
  static const Color n500 = Color(0xFF6B8579);
  static const Color n700 = Color(0xFF4B6358);
  static const Color n900 = Color(0xFF1E3A2F);
}

class AppColors {
  // ── brand ──────────────────────────────────────────────────────────
  /// Green as text and icon, and a dark fill behind white text: links, the
  /// selected tab's label, focus rings, the map's centre button. 5.48:1
  /// on white, 5.24:1 on the page, 4.99:1 on the tint; white on it 5.48:1.
  static const Color primary = Color(0xFF047857);

  /// An outline under the finger. 3.77:1, enough for an edge, not text.
  static const Color primaryLight = Color(0xFF059669);

  /// The soft emerald tint: icon tiles, a selected row, a chip, the
  /// progress track. [primary] on it 4.99:1.
  static const Color primaryContainer = Color(0xFFDCFCE7);

  /// The main action: one filled button per screen, the selected tab's
  /// pill, the floating button. Emerald, never text: 2.54:1 on white.
  static const Color action = Color(0xFF10B981);

  /// The main action pressed: kelly. [onAction] on it 6.7:1.
  static const Color actionHover = Color(0xFF22C55E);

  /// Text, icons and spinners on [action] and [actionHover]: 6.03:1 on the
  /// emerald, and still legible on a disabled button's [surfaceSunken].
  static const Color onAction = Color(0xFF0F2A20);

  /// Card edges and the app bar's rule: mid-light green. Decorative,
  /// 1.40:1, so a control a person must find has [border].
  static const Color edge = Color(0xFF86EFAC);

  /// Text and icons on any *dark* filled colour -- [primary] and every
  /// status colour. The lowest pairing, on [primary], is 5.48:1.
  static const Color onFill = Color(0xFFFFFFFF);

  /// The logo's red: the passenger's own stops on the journey strip and
  /// the map. Never a button fill, so a red SOS never sits beside a red
  /// "Book". 5.86:1 on white.
  static const Color brand = Color(0xFFC8151D);

  /// A light tint of [brand]. Pair with [brand] as text: 4.9:1.
  static const Color brandContainer = Color(0xFFFBE7E8);

  // ── semantic roles ─────────────────────────────────────────────────
  /// Confirmed, paid, boarded. 5.48:1; 4.99:1 on its container.
  static const Color success = Color(0xFF047857);
  static const Color successContainer = Color(0xFFDCFCE7);

  /// Awaiting payment, needs attention. 5.93:1; 5.42:1 on its container.
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFFFF4DB);

  /// Cancelled, failed, emergency. 6.54:1; 5.72:1 on its container.
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFFDECEA);

  /// Informational, neither good nor bad: "At terminal", "Pending sync".
  /// The type colour on a grey-green tint. 12.34:1; about 10:1 on it.
  static const Color info = AppRamp.n900;
  static const Color infoContainer = Color(0xFFE6EFEA);

  // ── neutrals ───────────────────────────────────────────────────────
  /// The page, behind every card: meadow mist.
  static const Color surface = AppRamp.n50;

  /// Cards, sheets, the app bar and the tab bar.
  static const Color surfaceRaised = AppRamp.n0;

  /// A step inside a card: a read-only field, a disabled button.
  static const Color surfaceSunken = AppRamp.n100;

  /// 12.34:1 on white, 11.79:1 on the page.
  static const Color textPrimary = AppRamp.n900;

  /// Secondary text is still text; "muted" is not licence to drop below
  /// AA. 6.51:1; 6.22:1 on the page, 5.93:1 on the tint.
  static const Color textMuted = AppRamp.n700;

  /// Boundary of an interactive control -- an input outline, a chip edge.
  /// Clears WCAG 1.4.11's 3:1: 4.00:1; 3.82:1 on the page.
  static const Color border = AppRamp.n500;

  /// Decorative separation only, where 1.4.11 does not apply.
  static const Color divider = AppRamp.n200;

  /// A disabled control's label and edge. Exempt as inactive UI.
  static const Color disabled = AppRamp.n400;

  /// Retained so the screen sweep can land file by file instead of in one
  /// 22-site commit. Points at [success]; remove once no call sites remain.
  @Deprecated('Use AppColors.success (or successContainer for a chip fill).')
  static const Color accent = success;
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

  /// Primary actions. Carried over deliberately: a Dispatcher works one
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
