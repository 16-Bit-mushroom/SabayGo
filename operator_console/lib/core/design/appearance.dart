import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'tokens.dart';

/// Dark or light, chosen with the sun/moon button in the top bar and
/// remembered by this browser.
///
/// Switching is two steps. [AppColors.use] swaps the palette every screen
/// reads, and the app root rebuilds [ThemeData] from it (it listens to
/// this notifier). Then every widget is redrawn with
/// [BindingBase.reassembleApplication] -- the mechanism behind hot reload --
/// because colours are read in some four hundred places, many inside
/// `const` widgets that an ordinary rebuild skips. Redrawing keeps each
/// widget's state, so the office stays on the same page with the same trip
/// selected.
///
/// Stored in `localStorage`, per browser: the console is Flutter Web only
/// (as `core/util/download.dart`). Storage that is blocked or full only
/// costs the remembering, never the switch.
class Appearance extends ChangeNotifier {
  Appearance() {
    AppColors.use(_saved() == 'light' ? AppPalette.light : AppPalette.dark);
  }

  static const _key = 'sabaygo.console.appearance';

  bool get isDark => AppColors.isDark;

  void toggle() {
    final next = isDark ? AppPalette.light : AppPalette.dark;
    AppColors.use(next);
    try {
      web.window.localStorage.setItem(_key, next == AppPalette.light ? 'light' : 'dark');
    } catch (_) {
      // Private window or blocked storage: the switch still happens.
    }
    notifyListeners();
    WidgetsBinding.instance.reassembleApplication();
  }

  static String? _saved() {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }
}
