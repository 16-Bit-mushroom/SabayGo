import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/boarding_audit/boarding_audit_screen.dart';
import '../../modules/disputes/disputes_screen.dart';
import '../../modules/driving_flags/driving_flags_screen.dart';
import '../../modules/remittance/remittance_screen.dart';
import '../../modules/setup/setup_screen.dart';
import '../../modules/start_review/start_review_screen.dart';
import '../../modules/van_board/van_board_screen.dart';
import '../../modules/special_trips/special_trips_screen.dart';
import '../../modules/messaging/screens/messages_screen.dart';
import '../../modules/live_map/screens/fleet_map_screen.dart';
import '../../modules/emergency/screens/sos_console_screen.dart';
import '../../modules/trip_monitor/screens/trip_monitor_screen.dart';
import '../../viewmodels/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/money_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../../viewmodels/notification_provider.dart';
import '../design/components/brand_logo.dart';
import '../design/components/focus_ring.dart';
import '../design/tokens.dart';
import 'notification_bell.dart';
import 'profile_dialog.dart';
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
  bool _collapsed = false;
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
      manager: _manager,
    );
  }

  @override
  void dispose() {
    _notifications.dispose();
    _reviews.dispose();
    super.dispose();
  }

  // Page and menu entry declared together, so inserting a page can never
  // point a notification at the wrong place. Emergencies is last: the
  // sidebar pins it to its foot.
  late final List<_Hub> _all = [
    _Hub('Overview', Icons.map_outlined, Icons.map, [_Page('Overview', const FleetMapScreen())]),
    _Hub('Trips', Icons.departure_board_outlined, Icons.departure_board, [
      _Page('Trips', const TripMonitorScreen()),
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
    _Hub('Money', Icons.receipt_long_outlined, Icons.receipt_long, [_Page('Remittance', const RemittanceScreen())]),
    _Hub('Messages', Icons.chat_bubble_outline, Icons.chat_bubble, [_Page('Messages', const MessagesScreen())]),
    _Hub('Setup', Icons.tune_outlined, Icons.tune,
        [_Page('Setup', SetupScreen(onOpenTrips: () => _show((w) => w is TripMonitorScreen)))]),
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

  /// Looked up by screen type rather than written out as an index. False
  /// when this person is not shown that page.
  bool _show(bool Function(Widget) test) {
    for (var h = 0; h < _hubs.length; h++) {
      final pages = _hubs[h].pagesFor(_manager);
      final t = pages.indexWhere((p) => test(p.screen));
      if (t >= 0) {
        setState(() {
          _hub = h;
          _tab[h] = t;
        });
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
                selected: _hub,
                collapsed: _collapsed,
                onSelect: (i) => setState(() => _hub = i),
                onToggle: () => setState(() => _collapsed = !_collapsed),
              )),
              Expanded(
                child: Column(
                  children: [
                    _region(2, _TopBar(
                      strip: TodayStrip(onOpen: _openToday),
                      bell: NotificationBell(onOpen: _openFor),
                    )),
                    if (pages.length > 1)
                      _region(3, _Tabs(
                        key: ValueKey(hub.label),
                        pages: pages,
                        selected: tab,
                        onSelect: (t) => setState(() => _tab[_hub] = t),
                      )),
                    Expanded(
                      child: _region(4,
                          KeyedSubtree(key: ValueKey('${hub.label}/$tab'), child: pages[tab].screen)),
                    ),
                  ],
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
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

// ------------------------------------------------------------------ top bar
class _TopBar extends StatelessWidget {
  const _TopBar({required this.strip, required this.bell});

  final Widget strip;
  final Widget bell;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: strip),
          const SizedBox(width: AppSpacing.md),
          bell,
          const SizedBox(width: AppSpacing.sm),
          const _ProfileMenu(),
        ],
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
        if (v == 'profile') {
          showDialog<void>(context: context, builder: (_) => const ProfileDialog());
        } else {
          auth.signOut();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'profile',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('My profile'),
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
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The mark is black ink on transparent and is drawn only on a
          // light surface, so it sits on its white plate.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
            child: BrandPlate(height: collapsed ? 24 : 40),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Text('A2Z cooperative office',
                  style: text.bodySmall!.copyWith(color: AppColors.onSidebarMuted)),
            ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (var i = 0; i < hubs.length; i++)
                  if (i != sos) item(i),
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

/// One entry. Selection is carried three ways -- a lighter fill, the icon
/// set on a white plate tile (the pila board's magnet), a bold label -- so
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
        ? tile(AppColors.onSidebar, hub.selectedIcon, hub.urgent ? AppColors.danger : AppColors.primary)
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
                color: AppColors.onSidebar,
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
            color: AppColors.onSidebar,
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
        color: AppColors.onSidebar,
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
