import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/boarding_audit/boarding_audit_screen.dart';
import '../../modules/door_cameras/door_cameras_screen.dart';
import '../../modules/disputes/disputes_screen.dart';
import '../../modules/driving_flags/driving_flags_screen.dart';
import '../../modules/remittance/remittance_screen.dart';
import '../../modules/setup/setup_screen.dart';
import '../../modules/setup/setup_status.dart' show SetupStep;
import '../../modules/start_review/start_review_screen.dart';
import '../../modules/van_board/van_board_screen.dart';
import '../../modules/schedule_management/screens/schedule_screen.dart';
import '../../modules/special_trips/special_trips_screen.dart';
import '../../modules/messaging/screens/messages_screen.dart';
import '../../modules/live_map/screens/fleet_map_screen.dart';
import '../../modules/emergency/screens/sos_console_screen.dart';
import '../../modules/trip_monitor/screens/trip_monitor_screen.dart';
import '../../viewmodels/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/money_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../../viewmodels/notification_provider.dart';
import '../design/components/brand_logo.dart';
import '../design/components/focus_ring.dart';
import '../design/tokens.dart';
import 'notification_bell.dart';
import 'account_screen.dart';
import 'console_router.dart';
import 'review_counts.dart';
import 'today_strip.dart';

/// Sidebar on the left, a top bar with today's figures, the bell and the
/// signed-in user, and the selected page beneath.
///
/// Seven menu entries, each a hub. Pages that answer the same question sit
/// as tabs under one entry -- Trips, Van Status Board and Special Trips are
/// all "what is running" -- so the menu stays short enough to read at a
/// glance (UI redesign v3). Each page keeps its own title, and that title
/// is its tab's label word for word. The menu keeps its labels: office
/// staff should never have to learn an icon to find a page.
class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _hub = 0;
  final Map<int, int> _tab = {};
  bool _account = false;
  /// The person's own choice of menu width; null until they make one.
  /// Until then the menu folds to its icons on a screen under 1500 px, so
  /// a laptop's trip sheet keeps its Next step column (12 Nov UI run: at
  /// 1440 px the sheet's actions were off the right edge).
  bool? _collapsedChoice;
  late final ConsoleLocation _location = context.read<ConsoleLocation>();
  late final NotificationProvider _notifications;
  late final ReviewCounts _reviews;
  late final bool _manager = context.read<AuthProvider>().profile?.role.isManager ?? false;

  @override
  void initState() {
    super.initState();
    // Live with the shell: polling starts at sign-in and stops at sign-out.
    _notifications = NotificationProvider(
      NotificationRepository(context.read<ApiClient>()),
    );
    _reviews = ReviewCounts(
      dispatch: context.read<DispatchRepository>(),
      oversight: context.read<OversightRepository>(),
      money: context.read<MoneyRepository>(),
      messaging: MessagingRepository(context.read<ApiClient>()),
      manager: _manager,
    );
    _read();
    _location.addListener(_onLocation);
  }

  @override
  void dispose() {
    _location.removeListener(_onLocation);
    _notifications.dispose();
    _reviews.dispose();
    super.dispose();
  }

  // Page and menu entry declared together, so inserting a page can never
  // point a notification at the wrong place. Emergencies is last: the
  // sidebar pins it to its foot.
  late final List<_Hub> _all = [
    _Hub('Overview', Icons.map_outlined, Icons.map, [
      _Page('Overview', const FleetMapScreen()),
      // What each van's phone reads at the door and how it holds up (12 Nov).
      _Page('Door cameras', const DoorCamerasScreen(), managerOnly: true),
    ]),
    _Hub('Trips', Icons.departure_board_outlined, Icons.departure_board, [
      _Page('Trips', const TripMonitorScreen()),
      // The timetable sits with the trips it makes and the post box that
      // posts it (11 Nov), not in Setup.
      _Page('Trip Schedules', TimetablePage(onOpenRoute: () {
        // Straight to Setup's Route step with its Add route form open.
        SetupScreen.requested = SetupStep.route;
        SetupScreen.requestAdd = true;
        _show((w) => w is SetupScreen);
      }), managerOnly: true),
      _Page('Van Status Board', const VanBoardScreen()),
      // The Terminal Manager and the Cashier both review requests and
      // enter walk-ins (brief 3).
      _Page('Special Trips', const SpecialTripsScreen()),
    ]),
    _Hub('Reviews', Icons.fact_check_outlined, Icons.fact_check, [
      _Page('Review Starts', const StartReviewScreen(), managerOnly: true, count: () => _reviews.starts),
      _Page('Boarding Audit', const BoardingAuditScreen(), managerOnly: true, count: () => _reviews.boardings),
      _Page('Driving Flags', const DrivingFlagsScreen(), count: () => _reviews.flags),
      _Page('Disputes', const DisputesScreen(), count: () => _reviews.disputes),
    ], count: () => _reviews.total),
    _Hub('Money', Icons.receipt_long_outlined, Icons.receipt_long, [_Page('Money', const RemittanceScreen())]),
    _Hub('Messages', Icons.chat_bubble_outline, Icons.chat_bubble, [_Page('Messages', const MessagesScreen())],
        count: () => _reviews.messages),
    _Hub('Setup', Icons.tune_outlined, Icons.tune,
        [_Page('Setup', SetupScreen(onOpenTimetable: () => _show((w) => w is TimetablePage)))]),
    _Hub('Emergencies (SOS)', Icons.emergency_outlined, Icons.emergency,
        [_Page('Emergencies (SOS)', const SosConsoleScreen())], urgent: true),
  ];

  /// The menu this person is shown. The Cashier records payments and does
  /// not decide what is owed, set rules or plan the timetable (brief
  /// section 3), so those pages are not offered rather than refused.
  late final List<_Hub> _hubs = [
    for (final h in _all)
      if (h.pagesFor(_manager).isNotEmpty) h,
  ];

  // The address is the page (console_router.dart): every way of opening a
  // page -- the menu, a tab, an alert, a figure in the top bar, the
  // browser's Back -- moves the address, and the shell follows it.
  void _onLocation() => setState(_read);

  /// The page the address names. Overview for an address that names no
  /// page, or a page this person is not shown.
  void _read() {
    final parts = _location.path.split('/').where((s) => s.isNotEmpty).toList();
    _account = parts.isNotEmpty && parts.first == 'account';
    if (_account) return;
    final h = parts.isEmpty ? -1 : _hubs.indexWhere((x) => slug(x.label) == parts.first);
    _hub = h < 0 ? 0 : h;
    if (parts.length > 1) {
      final t = _hubs[_hub].pagesFor(_manager).indexWhere((p) => slug(p.label) == parts[1]);
      if (t >= 0) _tab[_hub] = t;
    }
  }

  /// Opens a menu entry, on [tab] or on the tab last used there.
  void _go(int hub, [int? tab]) {
    final pages = _hubs[hub].pagesFor(_manager);
    final t = (tab ?? _tab[hub] ?? 0).clamp(0, pages.length - 1);
    _tab[hub] = t;
    final entry = slug(_hubs[hub].label);
    _location.go(pages.length > 1 ? '/$entry/${slug(pages[t].label)}' : '/$entry');
  }

  /// Looked up by screen type rather than written out as an index. False
  /// when this person is not shown that page.
  bool _show(bool Function(Widget) test) {
    for (var h = 0; h < _hubs.length; h++) {
      final t = _hubs[h].pagesFor(_manager).indexWhere((p) => test(p.screen));
      if (t >= 0) {
        _go(h, t);
        return true;
      }
    }
    return false;
  }

  /// The page an alert is about; the next one this person may open when
  /// that page is the Terminal Manager's.
  void _openFor(AppNotification n) {
    final _ = switch (n.type) {
      'sos_alert' => _show((w) => w is SosConsoleScreen),
      'capacity_alert' => _show((w) => w is BoardingAuditScreen) || _show((w) => w is VanBoardScreen),
      'departed_more_than_listed' => _show((w) => w is BoardingAuditScreen),
      'driving_flag' => _show((w) => w is DrivingFlagsScreen),
      'dispute_raised' => _show((w) => w is DisputesScreen),
      'left_unpaid' => _show((w) => w is RemittanceScreen),
      // A decision left the operator holding more than the share (038).
      'share_over_given' => _show((w) => w is RemittanceScreen),
      'special_trip_request' => _show((w) => w is SpecialTripsScreen),
      'unconfirmed_trip_start' => _show((w) => w is StartReviewScreen) || _show((w) => w is TripMonitorScreen),
      _ when n.isTripAlert => _show((w) => w is TripMonitorScreen),
      _ => false,
    };
  }

  void _openToday(TodayTarget target) => switch (target) {
        TodayTarget.fleet => _show((w) => w is FleetMapScreen),
        TodayTarget.trips => _show((w) => w is TripMonitorScreen),
        TodayTarget.review => _show((w) => w is BoardingAuditScreen) || _show((w) => w is VanBoardScreen),
        TodayTarget.emergencies => _show((w) => w is SosConsoleScreen),
      };

  @override
  Widget build(BuildContext context) {
    final hub = _hubs[_hub];
    final pages = hub.pagesFor(_manager);
    final tab = (_tab[_hub] ?? 0).clamp(0, pages.length - 1);
    final title = _account ? 'My account' : pages[tab].label;
    final collapsed = _collapsedChoice ?? MediaQuery.sizeOf(context).width < 1500;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationProvider>.value(value: _notifications),
        ChangeNotifierProvider<ReviewCounts>.value(value: _reviews),
      ],
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // Tab works through one region before the next -- the menu, the
        // top bar, the page's tabs, then the page -- instead of zig-zagging
        // by screen position between the rail and the page.
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            children: [
              _region(1, _Sidebar(
                hubs: _hubs,
                selected: _account ? -1 : _hub,
                collapsed: collapsed,
                onSelect: _go,
                onToggle: () => setState(() => _collapsedChoice = !collapsed),
              )),
              Expanded(
                child: _Ambient(
                  child: Column(
                  children: [
                    _region(2, _TopBar(
                      strip: TodayStrip(onOpen: _openToday),
                      bell: NotificationBell(onOpen: _openFor),
                    )),
                    if (!_account && pages.length > 1)
                      _region(3, _Tabs(
                        key: ValueKey(hub.label),
                        pages: pages,
                        selected: tab,
                        onSelect: (t) => _go(_hub, t),
                      )),
                    Expanded(
                      // The browser tab names the page, so several open
                      // tabs are told apart.
                      child: Title(
                        title: '$title | SabayGo',
                        color: AppColors.primary,
                        child: _region(4, _account
                            ? const KeyedSubtree(key: ValueKey('account'), child: AccountScreen())
                            : KeyedSubtree(key: ValueKey('${hub.label}/$tab'), child: pages[tab].screen)),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _region(double order, Widget child) =>
    FocusTraversalOrder(order: NumericFocusOrder(order), child: FocusTraversalGroup(child: child));

// --------------------------------------------------------------------- tabs
/// The hub's pages, as a standard tab bar under the top bar. A count sits
/// beside a tab only when it loaded and is above zero.
class _Tabs extends StatefulWidget {
  const _Tabs({super.key, required this.pages, required this.selected, required this.onSelect});

  final List<_Page> pages;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with SingleTickerProviderStateMixin {
  late final TabController _controller =
      TabController(length: widget.pages.length, initialIndex: widget.selected, vsync: this);

  @override
  void didUpdateWidget(_Tabs old) {
    super.didUpdateWidget(old);
    if (_controller.index != widget.selected) _controller.animateTo(widget.selected);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ReviewCounts>();
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: TabBar(
        controller: _controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        onTap: widget.onSelect,
        tabs: [
          for (final p in widget.pages)
            Tab(
              height: 46,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(p.label),
                if ((p.count?.call() ?? 0) > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _CountPill(p.count!()!),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

/// A figure waiting on a decision. Ochre: something to look at, not an
/// alarm -- the alarm is Emergencies' red.
class _CountPill extends StatelessWidget {
  const _CountPill(this.value, {this.onSidebar = false});
  final int value;
  final bool onSidebar;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: onSidebar ? AppColors.attention : AppColors.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '$value',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: onSidebar ? AppColors.onAttention : AppColors.warning,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- the surfaces
/// The page's light (11 Nov, "transparency"): the meadow mist with two
/// soft emerald glows, top right and bottom left, so the frosted bars and
/// the see-through washes have something to show. Behind the panels only;
/// every panel that holds data stays solid white, so no figure is read
/// through a gradient.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(1.1, -1.2),
            radius: 1.4,
            colors: [Color(0x2E22C55E), Color(0x0022C55E)],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.0, 1.3),
              radius: 1.2,
              colors: [Color(0x1F10B981), Color(0x0010B981)],
            ),
          ),
          child: child,
        ),
      );
}

/// A bar over the page -- the top bar, the hub's tabs: frosted glass,
/// white at 78 % over a 14 px blur, with a hairline under it.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.height, this.padding});
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: height,
            padding: padding,
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: AppColors.glass,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: child,
          ),
        ),
      );
}

// ------------------------------------------------------------------ top bar
class _TopBar extends StatelessWidget {
  const _TopBar({required this.strip, required this.bell});

  final Widget strip;
  final Widget bell;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Row(
        children: [
          Expanded(child: strip),
          const SizedBox(width: AppSpacing.md),
          const _RoleChip(),
          const SizedBox(width: AppSpacing.sm),
          bell,
          const SizedBox(width: AppSpacing.sm),
          const _ProfileMenu(),
        ],
      ),
    );
  }
}

/// The separation of duties, one click away (11 Nov, the owner's
/// reference): what this role may do, and what the other one does.
class _RoleChip extends StatelessWidget {
  const _RoleChip();

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().profile?.role;
    final manager = role?.isManager ?? false;
    final cashier = role?.isCashier ?? false;
    if (!manager && !cashier) return const SizedBox.shrink();
    final duties = manager
        ? const [
            'Keep the records: terminals, route, fares, trip schedules, staff, vans and phones, and the rules.',
            'Post trips for passengers and assign each one a van and a Dispatcher.',
            'Lift a trip\'s payment block, with a written reason.',
            'Review an automatic start, change a started trip\'s van, or void a trip.',
            'Decide disputes: upheld, rejected or adjusted.',
          ]
        : const [
            'Record the terminal fees the Dispatcher hands over, and the operator\'s share.',
            'Start a trip once its fees are recorded.',
            'Record an operator\'s dispute; the Terminal Manager decides it.',
          ];
    final other = manager
        ? 'The Cashier records the cash. The system holds no money.'
        : 'The Terminal Manager sets the rules, lifts payment blocks and decides disputes.';
    return Tooltip(
      message: manager ? 'What only the Terminal Manager can do' : 'What the Cashier does',
      child: ActionChip(
        avatar: Icon(manager ? Icons.verified_user_outlined : Icons.point_of_sale_outlined,
            size: 16, color: AppColors.primary),
        label: Text(manager ? 'Manager authority' : 'Cashier duties',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(manager ? 'As Terminal Manager you' : 'As Cashier you'),
            content: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final d in duties)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(d)),
                    ]),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(other, style: Theme.of(ctx).textTheme.bodySmall),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        ),
      ),
    );
  }
}

/// The signed-in person, and the two things people look for under their
/// own name: their profile and signing out.
class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.profile?.displayName ?? auth.profile?.email ?? '';
    final text = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      tooltip: 'My account',
      offset: const Offset(0, 52),
      onSelected: (v) {
        if (v == 'account') {
          context.read<ConsoleLocation>().go('/account');
        } else {
          auth.signOut();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'account',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('My account'),
          ),
        ),
        PopupMenuItem(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(color: AppColors.onFill, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                  Text(auth.profile?.role.title ?? 'A2Z office', style: text.bodySmall),
                ],
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sidebar
/// The terminal-green rail. Emergencies is pinned at its foot, apart from
/// the rest, so it is in the same place on every page.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.hubs,
    required this.selected,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
  });

  final List<_Hub> hubs;
  final int selected;
  final bool collapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final counts = context.watch<ReviewCounts>();
    Widget item(int i) => _SidebarItem(
          hub: hubs[i],
          count: hubs[i].count?.call(),
          selected: i == selected,
          collapsed: collapsed,
          onTap: () => onSelect(i),
        );
    final sos = hubs.indexWhere((h) => h.urgent);
    // Rebuilt when the counts change; read here so the watch is not lost.
    counts.total;
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : AppDuration.normal,
      curve: Curves.easeOut,
      width: collapsed ? 76 : 248,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.sidebarEdge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The logo on the white sidebar: whole when the menu is open, the
          // van alone when it is folded to icons.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
            child: Center(
              child: collapsed
                  ? const BrandLogo(mark: true, height: 30, width: 52)
                  : const BrandLogo(height: 80),
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 0),
              child: Text('A2Z cooperative office',
                  textAlign: TextAlign.center,
                  style: text.bodySmall!.copyWith(color: AppColors.onSidebarMuted)),
            ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              // Grouped as the work goes: the day's pages, then the set-up.
              children: [
                if (!collapsed) const _SectionName('Daily work'),
                for (var i = 0; i < hubs.length; i++)
                  if (i != sos) ...[
                    if (hubs[i].label == 'Setup')
                      collapsed
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                              child: Divider(color: AppColors.sidebarEdge, height: 1))
                          : const _SectionName('System'),
                    item(i),
                  ],
              ],
            ),
          ),
          if (sos >= 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xs),
              child: item(sos),
            ),
          Divider(color: AppColors.sidebarEdge, height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: _SidebarButton(
              icon: collapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
              label: collapsed ? 'Show menu names' : 'Hide menu names',
              collapsed: collapsed,
              onTap: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry. Selection is carried three ways -- the emerald fill, the
/// icon set on a white tile (the pila board's magnet), a bold label -- so
/// it never rests on hue alone (WCAG 1.4.1). Emergencies keeps a red icon
/// tile in every state and turns red when open: it is the one page that is
/// an alarm.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.hub,
    required this.count,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _Hub hub;
  final int? count;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = hub.urgent ? AppColors.danger : AppColors.sidebarSelected;
    final showCount = (count ?? 0) > 0;
    // A 26 px tile holds the icon in every state, so entries never shift.
    Widget tile(Color? fill, IconData glyph, Color colour) => Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: fill == null
              ? null
              : BoxDecoration(color: fill, borderRadius: BorderRadius.circular(6)),
          child: Icon(glyph, size: 18, color: colour),
        );
    final icon = selected
        ? hub.urgent
            ? tile(AppColors.onFill, hub.selectedIcon, AppColors.danger)
            : tile(AppColors.surfaceRaised, hub.selectedIcon, AppColors.primary)
        : hub.urgent
            ? tile(AppColors.danger, hub.icon, AppColors.onFill)
            : tile(null, hub.icon, AppColors.onSidebarMuted);
    final row = Row(
      mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Badge(
          isLabelVisible: collapsed && showCount,
          backgroundColor: AppColors.attention,
          smallSize: 8,
          child: icon,
        ),
        if (!collapsed) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              hub.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // On the open Emergencies' red fill the label is white.
                color: !selected
                    ? AppColors.onSidebar
                    : hub.urgent
                        ? AppColors.onFill
                        : AppColors.onAction,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (showCount) _CountPill(count!, onSidebar: true),
        ],
      ],
    );
    final item = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: collapsed ? (showCount ? '${hub.label}, $count waiting' : hub.label) : null,
        child: Material(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: FocusRing(
            child: InkWell(
              hoverColor: AppColors.sidebarHover,
              focusColor: AppColors.sidebarHover,
              onTap: onTap,
              child: SizedBox(
                height: AppSizing.minTouchTarget - 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
                  child: row,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Folded to icons, the name is still one hover away. The label above
    // already names it for a screen reader.
    return collapsed
        ? Tooltip(message: hub.label, preferBelow: false, excludeFromSemantics: true, child: item)
        : item;
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Folded, the tooltip names it; open, the label does (both at once
    // read the name twice).
    final button = Semantics(
      button: true,
      child: FocusRing(
        child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: AppColors.sidebarHover,
        focusColor: AppColors.sidebarHover,
        onTap: onTap,
        child: SizedBox(
          height: AppSizing.minTouchTarget - 4,
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (!collapsed) const SizedBox(width: AppSpacing.md),
              Icon(icon, size: 20, color: AppColors.onSidebarMuted),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.md),
                Text(label, style: TextStyle(color: AppColors.onSidebarMuted, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      ),
    );
    // Always wrapped, so folding the menu does not rebuild the button and
    // drop the keyboard focus that just pressed it.
    return Tooltip(message: label, excludeFromSemantics: !collapsed, child: button);
  }
}

/// One menu entry and the pages under it.
class _Hub {
  _Hub(this.label, this.icon, this.selectedIcon, this.pages, {this.urgent = false, this.count});

  /// The menu label. A one-page hub's page carries the same title.
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final List<_Page> pages;

  /// Drawn in the danger colour and pinned to the sidebar's foot. Only
  /// Emergencies.
  final bool urgent;

  /// What waits on a decision across the hub's pages; null when unknown.
  final int? Function()? count;

  List<_Page> pagesFor(bool manager) => [for (final p in pages) if (manager || !p.managerOnly) p];
}

/// One page: its tab label, which is its title word for word.
class _Page {
  _Page(this.label, this.screen, {this.managerOnly = false, this.count});

  final String label;
  final Widget screen;

  /// Hidden from the Cashier; the Terminal Manager's decisions.
  final bool managerOnly;

  final int? Function()? count;
}

/// A group's name in the sidebar: "Daily work", "System". Sentence case,
/// muted, and a heading for a screen reader.
class _SectionName extends StatelessWidget {
  const _SectionName(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Semantics(
          header: true,
          child: Text(name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, color: AppColors.onSidebarMuted)),
        ),
      );
}
