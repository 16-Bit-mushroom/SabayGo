import 'package:flutter/material.dart';

/// The console's place in the address bar: one location per page
/// (`/money`, `/trips/van-status-board`, `/account`).
///
/// Before this the page lived only in the shell's state, so a refresh
/// always landed on Overview, the browser's Back button left the console,
/// and no page could be bookmarked. Office staff refresh by habit, and
/// someone new to the console finds their way back with Back. Now the
/// address is the page: refresh keeps it, Back and Forward move between
/// pages, and a link opens the page after sign-in.
///
/// The URLs are hash URLs (`#/money`), Flutter Web's default, because the
/// bundle is served by a plain static server that has nothing at `/money`
/// to answer a refresh with.
class ConsoleLocation extends ChangeNotifier {
  String _path = '/';

  String get path => _path;

  void go(String path) {
    if (path == _path) return;
    _path = path;
    notifyListeners();
  }
}

class ConsoleRouteParser extends RouteInformationParser<String> {
  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) async {
    final path = routeInformation.uri.path;
    return path.isEmpty ? '/' : path;
  }

  @override
  RouteInformation restoreRouteInformation(String configuration) =>
      RouteInformation(uri: Uri(path: configuration));
}

/// One page in the navigator, always: the pages themselves are switched by
/// the shell from [ConsoleLocation]. The navigator is still needed for
/// dialogs, menus and snackbars.
class ConsoleRouterDelegate extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  ConsoleRouterDelegate(this.location, this.child) {
    location.addListener(_changed);
  }

  /// A new page closes whatever dialog or menu was open over the old one.
  /// Without this, Back pressed under a dialog left it on screen over the
  /// new page, and a dialog that closes through its page's context could
  /// no longer close at all (found in the 10 Nov alpha run).
  void _changed() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }

  final ConsoleLocation location;
  final Widget child;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  String get currentConfiguration => location.path;

  @override
  Future<void> setNewRoutePath(String configuration) async => location.go(configuration);

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [MaterialPage(child: child)],
        onDidRemovePage: (_) {},
      );

  @override
  void dispose() {
    location.removeListener(_changed);
    super.dispose();
  }
}

/// A page's label as an address segment: "Van Status Board" ->
/// "van-status-board", "Emergencies (SOS)" -> "emergencies-sos".
String slug(String label) =>
    label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
