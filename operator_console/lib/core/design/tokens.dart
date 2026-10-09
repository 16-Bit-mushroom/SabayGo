import 'package:flutter/material.dart';

/// Design tokens for the coop_admin console.
///
/// **Dark, and deliberately apart from `mobile/`.** The console began as a
/// copy of the handset tokens (light: ink on white, the SABAY GO owl's
/// colours). It was redesigned in October 2026 as an operations dashboard
/// -- near-black canvas, grey panels, a light action colour -- because the
/// office watches a live map and a trip board for a whole shift, and a
/// dark surface lets the map, the status colours and the numbers carry the
/// page instead of the white space around them. The handset stays light:
/// a conductor reads it at a van door in direct sunlight, which is the one
/// place a dark UI is genuinely worse. Changing a value here no longer
/// means changing it there.
///
/// **Every pairing below is measured against WCAG 2.1 AA** (ratios in the
/// comments are computed, not estimated). Three rules the palette keeps:
///
/// 1. A status colour is bright enough to be *text on any panel*, and
///    anything drawn *on* a filled colour -- a button, a badge, a chip --
///    uses [onFill]. On a dark UI those are two different constraints, so
///    they are two tokens; on the old light palette one colour did both.
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container` tint so a chip can state its meaning in
///    words, and callers include the label or an icon, not just the colour.
/// 3. Anything a pointer lands on is at least [AppSizing.minTouchTarget].
class AppColors {
  // ── action ─────────────────────────────────────────────────────────
  // The owl's *ink* became the light action colour: on a dark canvas the
  // highest-contrast thing a page can offer is near-white, which is what
  // "ink" meant on paper. Selected navigation, filled buttons, focus rings.
  // The logo's *red* keeps its one job -- route geometry and alarms -- and
  // is never a button fill, so a red SOS never sits beside a red "Save".

  /// Light action fill. 15.1:1 on [surfaceRaised]; [onFill] on it 15.9:1.
  static const Color primary = Color(0xFFECECF0);

  /// Pressed / secondary action shade.
  static const Color primaryLight = Color(0xFFC9CAD2);

  /// Neutral tint behind [primary] text (selected chip, avatar): 12.0:1.
  static const Color primaryContainer = Color(0xFF2A2B31);

  /// Text and icons drawn on any *filled* colour token -- [primary] and
  /// every status colour. Lowest pairing is on [danger], 6.8:1.
  static const Color onFill = Color(0xFF111216);

  /// The logo's red, lifted for a dark canvas. 4.85:1 on [surfaceRaised].
  /// For markers, route geometry and the SOS entry -- not body text.
  static const Color brand = Color(0xFFF0484F);
  static const Color brandContainer = Color(0xFF3A1719);

  /// The selected thing on the map: the chosen van's halo, its route line,
  /// trip progress. One hue so the eye finds "what I clicked" at once.
  /// 13.6:1 on [surfaceRaised].
  static const Color highlight = Color(0xFFC8F051);

  // ── semantic roles ─────────────────────────────────────────────────
  /// Confirmed, paid, boarded, live. 10.2:1 on [surfaceRaised], 8.2:1 on
  /// [successContainer].
  static const Color success = Color(0xFF4ADE80);
  static const Color successContainer = Color(0xFF12301F);

  /// Awaiting payment, a difference to look at. 10.0:1 on
  /// [surfaceRaised], 8.2:1 on [warningContainer].
  static const Color warning = Color(0xFFF5B841);
  static const Color warningContainer = Color(0xFF33270E);

  /// Cancelled, failed, emergency. 6.4:1 on [surfaceRaised], 5.8:1 on
  /// [dangerContainer].
  static const Color danger = Color(0xFFF87171);
  static const Color dangerContainer = Color(0xFF3A1719);

  /// Informational, neither good nor bad: "At terminal", "Scheduled".
  /// 7.3:1 on [surfaceRaised], 6.0:1 on [infoContainer].
  static const Color info = Color(0xFF6AA9FA);
  static const Color infoContainer = Color(0xFF14294A);

  // ── neutrals ───────────────────────────────────────────────────────
  /// The page canvas, behind every panel.
  static const Color surface = Color(0xFF0E0F12);

  /// Panels and cards -- where the data sits.
  static const Color surfaceRaised = Color(0xFF17181C);

  /// A step inside a panel: table headers, read-only fields, hover rows,
  /// the inner tiles of a card.
  static const Color surfaceSunken = Color(0xFF1F2025);

  /// The sidebar and the top bar: a shade off the canvas so the frame is
  /// visible without competing with the panels it holds.
  static const Color sidebar = Color(0xFF131418);

  /// 15.9:1 on [surfaceRaised].
  static const Color textPrimary = Color(0xFFF2F2F5);

  /// 7.3:1 on [surfaceRaised], 6.7:1 on [surfaceSunken]. Secondary text is
  /// still text; "muted" is not licence to drop below AA.
  static const Color textMuted = Color(0xFFA3A6B0);

  /// Boundary of an interactive control -- an input outline, a chip edge.
  /// 3.75:1 on [surfaceRaised], 3.44:1 on [surfaceSunken]: clears WCAG
  /// 1.4.11's 3:1 so a field has a perceivable edge. Use [divider] for
  /// decoration.
  static const Color border = Color(0xFF70737E);

  /// Decorative separation only, where nothing must be located by it.
  static const Color divider = Color(0xFF2B2D33);
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
