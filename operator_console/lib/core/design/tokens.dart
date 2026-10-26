import 'package:flutter/material.dart';

/// Design tokens for the office console.
///
/// **One light palette: the terminal's pila board.** Redesigned in
/// October 2026 (UI redesign v3) after the dark "Night Owl's Ledger" was
/// retired: whiteboard white is the page (about 60 % of it), terminal
/// green is the frame and the action colour (about 30 %: the sidebar, the
/// selected entry, primary buttons), and marker black and red are the ink
/// (about 10 %: text, and red only for SOS, danger and route pins). Light
/// only, for a bright office and a projector.
///
/// **Every pairing below is measured against WCAG 2.1 AA** (ratios are
/// computed, not estimated). Three rules they keep:
///
/// 1. A status colour is legible as *text on any panel*, and anything
///    drawn *on* a filled colour -- a button, a badge, a pin -- uses
///    [AppColors.onFill].
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container` tint so a chip can state its meaning in
///    words, and callers include the label or a mark, not just the colour.
/// 3. Anything a pointer lands on is at least [AppSizing.minTouchTarget].
///
/// Neutrals come from one fixed green-grey ramp ([AppRamp]); no screen
/// mixes its own grey.
class AppRamp {
  static const Color n0 = Color(0xFFFFFFFF);
  static const Color n50 = Color(0xFFF3F6F3);
  static const Color n100 = Color(0xFFEEF3EF);
  static const Color n200 = Color(0xFFDCE4DE);
  static const Color n400 = Color(0xFF9AA79E);
  static const Color n500 = Color(0xFF7A867C);
  static const Color n700 = Color(0xFF4E5A52);
  static const Color n900 = Color(0xFF121712);
}

/// The palette. Ratios are against white ([surfaceRaised]) unless stated.
class AppColors {
  /// The action colour: filled buttons, focus, the avatar. Terminal green.
  /// 7.98:1; white on it 7.98:1.
  static const Color primary = Color(0xFF0B5D35);

  /// Pressed / hovered primary.
  static const Color primaryLight = Color(0xFF0E6E40);

  /// Green tint: the head of the set-up queue, a selected chip.
  /// [primary] on it 6.84:1.
  static const Color primaryContainer = Color(0xFFE3F1E7);

  /// Text and icons on any *filled* colour -- [primary], [highlight] and
  /// every status colour. The lowest pairing, on [warning], is 5.93:1.
  static const Color onFill = Color(0xFFFFFFFF);

  /// The logo's red: route geometry and markers on the map. Never a
  /// button fill, so a red SOS never sits beside a red "Save". 5.86:1.
  static const Color brand = Color(0xFFC8151D);
  static const Color brandContainer = Color(0xFFFBE7E8);

  /// Behind the logo. The mark is black ink on transparent and is drawn
  /// only on a light surface.
  static const Color logoPlate = Color(0xFFFFFFFF);

  /// The selected thing on the map: the chosen van, its route line, trip
  /// progress. Marker black, so it reads as neither "go" nor "paid" nor
  /// "danger". 18.15:1; white on it the same.
  static const Color highlight = AppRamp.n900;

  /// Confirmed, paid, boarded, live. 6.13:1; 5.12:1 on its container.
  static const Color success = Color(0xFF00713C);
  static const Color successContainer = Color(0xFFE0EEE8);

  /// Awaiting payment, a difference to look at. 5.93:1; 5.13:1 on its
  /// container.
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFF6EEDC);

  /// Cancelled, failed, emergency. 6.54:1; 5.37:1 on its container.
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFF6E5E4);

  /// Informational, neither good nor bad: "At terminal", "Scheduled".
  /// Marker ink, not a fourth hue: the palette is white, green and
  /// black/red. 18.15:1; 15.9:1 on its container; white on it 18.15:1.
  static const Color info = AppRamp.n900;
  static const Color infoContainer = Color(0xFFE6ECE8);

  /// A count waiting on a decision, on the green sidebar: amber with
  /// [onAttention] text, 10.21:1.
  static const Color attention = Color(0xFFF5B841);
  static const Color onAttention = AppRamp.n900;

  /// The page canvas, behind every panel.
  static const Color surface = AppRamp.n50;

  /// Panels, cards, the top bar and the tab bar -- where the data sits.
  static const Color surfaceRaised = AppRamp.n0;

  /// A step inside a panel: table headers, read-only fields, hover rows.
  static const Color surfaceSunken = AppRamp.n100;

  /// The sidebar: painted terminal-green steel. White on it 7.98:1.
  static const Color sidebar = Color(0xFF0B5D35);

  /// The selected entry's fill, a step lighter. White on it 5.49:1. The
  /// fill alone is not the cue: the icon also sits on a white plate tile
  /// and the label turns bold.
  static const Color sidebarSelected = Color(0xFF18784A);

  /// Hovered entry: a white wash over the green.
  static const Color sidebarHover = Color(0x1AFFFFFF);

  /// The rule above the sidebar's fold button. Decorative.
  static const Color sidebarEdge = Color(0xFF2C7A52);

  static const Color onSidebar = Color(0xFFFFFFFF);

  /// Unselected icons and captions on the sidebar. 5.93:1.
  static const Color onSidebarMuted = Color(0xFFCFE3D6);

  /// 18.15:1 on white, 16.67:1 on the canvas.
  static const Color textPrimary = AppRamp.n900;

  /// Secondary text is still text; "muted" is not licence to drop below
  /// AA. 7.22:1; 6.43:1 on [surfaceSunken].
  static const Color textMuted = AppRamp.n700;

  /// Boundary of an interactive control -- an input outline, a chip edge.
  /// Clears WCAG 1.4.11's 3:1: 3.80:1; 3.38:1 on [surfaceSunken].
  static const Color border = AppRamp.n500;

  /// Decorative separation only, where nothing must be located by it.
  static const Color divider = AppRamp.n200;

  /// A disabled control's edge and a waiting queue tile. Exempt from
  /// contrast as inactive UI.
  static const Color disabled = AppRamp.n400;

  /// Behind a dialog or the notification sheet.
  static const Color scrim = Color(0x73121712);

  /// The only shadows in the console: things floating over map tiles.
  static const Color mapShadow = Color(0x66000000);
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
