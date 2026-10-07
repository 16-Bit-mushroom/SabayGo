import 'package:flutter/material.dart';

/// Design tokens for the coop_admin console.
///
/// A copy of `mobile/lib/core/design/tokens.dart`, kept value-for-value in
/// step, plus the few roles only a desktop dashboard needs ([surfaceSunken],
/// [sidebar]). Copied rather than shared because the two apps are separate
/// Flutter packages and a third package for one file is more machinery than
/// the problem. If you change a value here, change it there.
///
/// The console was a dark Nord palette with no token layer: about 300 raw
/// `Colors.*` / `Color(0x...)` uses, `white38` captions at 3.6:1 on the
/// canvas, and the same red written out twenty times. Office staff read it
/// for a full shift, at a desk, often in a bright room, where light
/// surfaces with dark text are the less fatiguing choice.
///
/// **Every colour pair here is verified against WCAG 2.1 AA**, and the
/// ratios in the comments are measured, not estimated. Three rules the
/// palette exists to keep:
///
/// 1. A base colour serves both as *text on a light background* and as *a
///    fill behind white text*, because both reduce to the same constraint:
///    contrast against white of at least 4.5:1. One token, two jobs, no
///    chance of the pair drifting apart.
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container`/`on` pair so a chip can state its meaning in
///    words on a legible tint, and callers are expected to include the
///    label or an icon, not just the colour.
/// 3. Anything a finger lands on is at least [minTouchTarget].
///
/// The previous palette failed AA in two places that mattered most: the
/// green `accent` (3.11:1) and the amber `warning` (1.97:1) were used for
/// boarding status and unpaid-fare warnings — information a conductor reads
/// at a van door in direct sunlight. Both are corrected below.
class AppColors {
  // ── brand ──────────────────────────────────────────────────────────
  // The SABAY GO mark is an ink-black owl with a red eye and a red route
  // pin. Those two colours split into two jobs, deliberately unequal.
  //
  // *Ink* is the action colour: every filled button, focus ring, selected
  // tab. Black on white is the highest contrast a light UI can offer, and
  // it is the colour a passenger already reads as "the text you act on".
  //
  // *Red* is the accent, spent sparingly on route geometry — the passenger's
  // own boarding and alighting stops, the way the logo's pin marks a
  // destination. It is never a button fill. A red "Book" sitting beside a
  // red "Cancel booking" and a red SOS would make all three look equally
  // alarming, and a colour used everywhere stops drawing the eye anywhere
  // (Von Restorff). Red keeps one meaning on an action: stop, or danger.

  /// Ink, from the owl. 18.0:1 on white. Was the old purple #2D2059.
  static const Color primary = Color(0xFF16161D);

  /// 11.2:1 on white. Secondary surfaces and pressed states.
  static const Color primaryLight = Color(0xFF3A3A44);

  /// Neutral tint behind [primary] text (selected pill, brand chip): 15.3:1.
  static const Color primaryContainer = Color(0xFFECECF0);

  /// The logo's red. 5.86:1 on white, so it may carry text, but it is meant
  /// for markers and accents — see the note above.
  static const Color brand = Color(0xFFC8151D);

  /// A light tint of [brand]. Pair with [brand] as text: 4.9:1.
  static const Color brandContainer = Color(0xFFFBE7E8);

  // ── semantic roles ─────────────────────────────────────────────────
  /// Confirmed, paid, boarded. 6.13:1 on white, 5.12:1 on
  /// [successContainer].
  ///
  /// Was `accent` at #00A859 — 3.11:1, which failed even the 3:1 floor for
  /// large text. Darkened along its own hue so the brand's green reads the
  /// same, and now carries text.
  static const Color success = Color(0xFF00713C);
  static const Color successContainer = Color(0xFFE0EEE8);

  /// Awaiting payment, variance, needs attention. 5.93:1 on white, 5.00:1
  /// on [warningContainer].
  ///
  /// Was #F9A825 at 1.97:1 — the worst failure in the app. Amber cannot be
  /// legible on white at full brightness; it has to become a dark ochre, or
  /// move to a tinted chip. Both options are provided.
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFF1EBE0);

  /// Cancelled, failed, emergency. 6.54:1 on white, 5.37:1 on
  /// [dangerContainer].
  ///
  /// Nudged from #D32F2F (4.98:1 — compliant but thin) for headroom, since
  /// this is the SOS colour and the one that must survive a cheap screen in
  /// daylight.
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFF6E5E4);

  /// Informational, not good or bad: "AT TERMINAL", "PENDING SYNC".
  /// 5.75:1 on white, 4.74:1 on [infoContainer].
  ///
  /// Exists because the screens reached for `Colors.blue` (3.12:1),
  /// `Colors.teal` (3.67:1) and `Colors.deepOrange` (3.16:1) when no token
  /// fitted. All three fail AA as text. A missing token is not a neutral
  /// omission — it gets filled in by whatever the framework offers.
  static const Color info = Color(0xFF1565C0);
  static const Color infoContainer = Color(0xFFE3EAF2);

  // ── neutrals ───────────────────────────────────────────────────────
  static const Color surface = Color(0xFFF7F7FA);
  static const Color surfaceRaised = Color(0xFFFFFFFF);

  /// Recessed areas inside a white panel: table headers, read-only fields,
  /// the hover row. A step down from [surface] so a panel's structure shows
  /// without borders on every cell.
  static const Color surfaceSunken = Color(0xFFF0F0F4);

  /// The sidebar. White like the panels, separated by a [divider] rule
  /// rather than a dark slab -- the navigation recedes, the data leads.
  static const Color sidebar = Color(0xFFFFFFFF);

  /// 17.06:1 on white.
  static const Color textPrimary = Color(0xFF1A1A2E);

  /// 6.73:1 on white. Darkened from #6B6B80; secondary text is still text,
  /// and "muted" is not licence to drop below AA.
  static const Color textMuted = Color(0xFF5A5A6E);

  /// Boundary of an interactive control — an input outline, a chip edge.
  /// 3.64:1 on white, 3.41:1 on [surface], clearing WCAG 1.4.11's 3:1 for
  /// non-text contrast.
  ///
  /// The old #DDDDE5 was 1.35:1. That is invisible as a boundary, and a
  /// white filled field on a #F7F7FA scaffold is only 1.07:1, so the fill
  /// could not delimit the control either — the field had no perceivable
  /// edge at all. Use [divider] for decoration; use this for anything a
  /// user must locate in order to operate.
  static const Color border = Color(0xFF84849C);

  /// Decorative separation only, where 1.4.11 does not apply because
  /// nothing needs to be identified by it.
  static const Color divider = Color(0xFFDDDDE5);

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
