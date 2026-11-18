import 'package:flutter/material.dart';

/// Design tokens for the office console.
///
/// **One light palette: balanced mid-green** (10 Nov, the owner's
/// VerdantPulse reference, replacing the monochromatic emerald). A soft
/// meadow-mist page, white and soft-emerald cards with mid-light green
/// edges, Kelly and emerald accents, and slate green-grey type:
///
///   F0FDF4 meadow mist      the page
///   FFFFFF / DCFCE7         cards; the soft emerald tint
///   86EFAC                  card and panel edges, the sidebar's edge
///   22C55E kelly            the progress bars' start
///   10B981 emerald          accents: the live dot, charts, the progress
///                           bars' end
///   059669                  secondary hover: an outline under the pointer
///   047857 forest           the main action and the selected sidebar
///                           entry, with white text; green text and icons,
///                           focus, success
///   065F46                  the main action hovered
///   1E3A2F slate green-grey the type
///
/// **Every pairing below is measured against WCAG 2.1 AA** (ratios are
/// computed, not estimated). The reference's white text on emerald is
/// 2.54:1, so the emerald and the kelly carry no text: a fill with a
/// label is the forest 047857, which is also green *text*, the shade that
/// passes on every surface here.
/// Three rules:
///
/// 1. A status colour is legible as *text on any panel*, and anything
///    drawn *on* a dark filled colour is light: [AppColors.onFill], or
///    [AppColors.onAction] on the main action.
/// 2. Status is never carried by hue alone (WCAG 1.4.1). Every semantic
///    role ships a `container` tint so a chip can state its meaning in
///    words, and callers include the label or a mark, not just the colour.
/// 3. Anything a pointer lands on is at least [AppSizing.minTouchTarget].
///
/// Neutrals come from one fixed green-grey ramp ([AppRamp]); no screen
/// mixes its own grey.
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

/// The palette. Ratios are against white ([surfaceRaised]) unless stated.
class AppColors {
  /// Green as text and icon: links, the selected tab, focus rings, the
  /// avatar, a done queue tile. 5.48:1; 5.24:1 on the page, 4.99:1 on the
  /// tint; white on it 5.48:1.
  static const Color primary = Color(0xFF047857);

  /// A dark-green fill or an outline, hovered: the reference's secondary
  /// hover. 3.77:1 against white, enough for an edge, not for text.
  static const Color primaryLight = Color(0xFF059669);

  /// The soft emerald tint: tinted cards, icon tiles, a selected row or
  /// chip, the progress track. [primary] on it 4.99:1.
  static const Color primaryContainer = Color(0xFFDCFCE7);

  /// The main action: filled buttons (one per view) and the selected
  /// sidebar entry. Forest, so its label is white (17 Nov, the owner: a
  /// dark fill carries light text). The emerald it replaced could not:
  /// white on it is 2.54:1.
  static const Color action = Color(0xFF047857);

  /// The main action under the pointer: a step darker. [onAction] on it
  /// 7.68:1.
  static const Color actionHover = Color(0xFF065F46);

  /// Text and icons on [action] and [actionHover]: white, 5.48:1 on the
  /// forest.
  static const Color onAction = Color(0xFFFFFFFF);

  /// Emerald as decoration only: the live dot, chart fills, the accent bar
  /// of a hovered row, the "On the road" shade. Never a fill under text
  /// (white on it 2.54:1) and never text (2.54:1 on white).
  static const Color accent = Color(0xFF10B981);

  /// The sidebar's edge and chart accents: mid-light green. Cards and
  /// panels take the lighter [divider] since 10 Nov (toned down), so green
  /// is left for the main action and paid/live states. Decorative, 1.40:1,
  /// so a control a person must find has [border].
  static const Color edge = Color(0xFF86EFAC);

  /// The progress bars run kelly to emerald on the [primaryContainer]
  /// track.
  static const Color progressStart = Color(0xFF22C55E);
  static const Color progressEnd = action;

  /// Kept from the previous palette for the logo plate's surroundings.
  static const Color mint = Color(0xFF9FFFCC);

  /// Text and icons on any *dark* filled colour -- [primary], [highlight]
  /// and every status colour. The lowest pairing, on [primary], is 5.48:1.
  static const Color onFill = Color(0xFFFFFFFF);

  /// The logo's red: route geometry and markers on the map. Never a
  /// button fill, so a red SOS never sits beside a red "Save". 5.86:1.
  static const Color brand = Color(0xFFC8151D);
  static const Color brandContainer = Color(0xFFFBE7E8);

  /// Behind the logo. The mark is black ink on transparent and is drawn
  /// only on a light surface.
  static const Color logoPlate = Color(0xFFFFFFFF);

  /// The selected thing on the map: the chosen van, its route line, trip
  /// progress. The type colour, so it reads as neither "go" nor "paid" nor
  /// "danger". 12.34:1; white on it the same.
  static const Color highlight = AppRamp.n900;

  /// Confirmed, paid, boarded, live. 5.48:1; 4.99:1 on its container.
  static const Color success = Color(0xFF047857);
  static const Color successContainer = Color(0xFFDCFCE7);

  /// Awaiting payment, a difference to look at. 5.93:1; 5.42:1 on its
  /// container.
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFFFF4DB);

  /// Cancelled, failed, emergency. 6.54:1; 5.72:1 on its container.
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFFDECEA);

  /// Informational, neither good nor bad: "At terminal", "Scheduled".
  /// The type colour on a grey-green tint. 12.34:1; about 10:1 on it.
  static const Color info = AppRamp.n900;
  static const Color infoContainer = Color(0xFFE6EFEA);

  /// A count waiting on a decision, on the sidebar: the soft tint with
  /// green text, 4.99:1.
  static const Color attention = primaryContainer;
  static const Color onAttention = primary;

  /// The page canvas, behind every panel: meadow mist.
  static const Color surface = AppRamp.n50;

  /// Panels, cards, the top bar and the tab bar -- where the data sits.
  static const Color surfaceRaised = AppRamp.n0;

  /// A step inside a panel: table headers, read-only fields, hover rows.
  static const Color surfaceSunken = AppRamp.n100;

  /// The sidebar: white, with an [edge] on its right, as in the reference.
  static const Color sidebar = AppRamp.n0;

  /// The selected entry: the forest, a bold white [onAction] label
  /// (5.48:1), and its icon on a white tile. The tile and the weight carry the
  /// selection as well as the fill.
  static const Color sidebarSelected = action;

  /// Hovered entry: a see-through green wash.
  static const Color sidebarHover = Color(0x1A10B981);

  /// The sidebar's right edge and the rule above its fold button.
  static const Color sidebarEdge = edge;

  /// Entry labels, 12.34:1.
  static const Color onSidebar = AppRamp.n900;

  /// Unselected icons, section names and the caption under the logo.
  /// 6.51:1.
  static const Color onSidebarMuted = AppRamp.n700;

  /// 12.34:1 on white, 11.79:1 on the page.
  static const Color textPrimary = AppRamp.n900;

  /// Secondary text is still text; "muted" is not licence to drop below
  /// AA. 6.51:1; 6.22:1 on the page, 5.93:1 on the tint.
  static const Color textMuted = AppRamp.n700;

  /// Boundary of an interactive control -- an input outline, a chip edge.
  /// Clears WCAG 1.4.11's 3:1: 4.00:1; 3.82:1 on the page.
  static const Color border = AppRamp.n500;

  /// Card and panel edges, rules inside a panel: table rows, column
  /// separators. Decorative.
  static const Color divider = AppRamp.n200;

  /// A disabled control's edge and a waiting queue tile. Exempt from
  /// contrast as inactive UI.
  static const Color disabled = AppRamp.n400;

  /// Behind a dialog or the notification sheet.
  static const Color scrim = Color(0x731E3A2F);

  /// Things floating over map tiles.
  static const Color mapShadow = Color(0x66000000);

  // ── interaction (11 Nov, "more lively, hover that works, transparency") ──
  // One set of see-through emerald washes for every pointer state, so a
  // table row, a card, a chip and a tab answer the pointer the same way.
  // They are tints over the surface, never a new colour: the text on them
  // keeps its measured contrast (primary on white + 8 % emerald is still
  // above 5:1).

  /// Under the pointer: 8 % emerald.
  static const Color hoverWash = Color(0x1410B981);

  /// Pressed, or a selected row under the pointer: 16 % emerald.
  static const Color pressWash = Color(0x2910B981);

  /// Keyboard focus inside a list: 12 % emerald (the ring carries it too).
  static const Color focusWash = Color(0x1F10B981);

  /// The bars that sit over the page -- the top bar and the hub's tabs:
  /// white at 78 %, blurred, so the page's light shows through.
  static const Color glass = Color(0xC7FFFFFF);

  /// The hover lift under a card or a main button: a soft green shadow.
  /// The second kind of shadow the console has, and only under the pointer.
  static const Color liftShadow = Color(0x2E047857);
}

/// The one hover lift: a card or a main button rises 2 px on this shadow.
class AppShadow {
  static const List<BoxShadow> none = [];
  static const List<BoxShadow> lift = [
    BoxShadow(color: AppColors.liftShadow, blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
  ];
  static const List<BoxShadow> rest = [
    BoxShadow(color: Color(0x0F047857), blurRadius: 6, offset: Offset(0, 1)),
  ];
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

  /// Every input, dropdown and picker box, and the buttons in a row with
  /// them: one height, so a row of fields lines up top and bottom and every
  /// box is the same target (Fitts).
  static const double field = 48;
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
