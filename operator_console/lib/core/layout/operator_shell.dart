import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/ai_audit_queue/screens/audit_dashboard_screen.dart';
import '../../modules/boarding_audit/boarding_audit_screen.dart';
import '../../modules/disputes/disputes_screen.dart';
import '../../modules/driving_flags/driving_flags_screen.dart';
import '../../modules/phones/phones_screen.dart';
import '../../modules/remittance/remittance_screen.dart';
import '../../modules/start_review/start_review_screen.dart';
import '../../modules/van_board/van_board_screen.dart';
import '../../modules/trip_dispatcher/screens/dispatch_board_screen.dart';
import '../../modules/fleet_management/screens/fleet_roster_screen.dart';
import '../../modules/schedule_management/screens/schedule_screen.dart';
import '../../modules/policy_editor/screens/policy_editor_screen.dart';
import '../../modules/revenue/screens/revenue_screen.dart';
import '../../modules/messaging/screens/messages_screen.dart';
import '../../modules/live_map/screens/fleet_map_screen.dart';
import '../../modules/emergency/screens/sos_console_screen.dart';
import '../../modules/trip_monitor/screens/trip_monitor_screen.dart';
import '../../viewmodels/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/notification_repository.dart';
import '../../viewmodels/notification_provider.dart';
import '../design/appearance.dart';
import '../design/components/brand_logo.dart';
import '../design/tokens.dart';
import 'notification_bell.dart';
import 'profile_dialog.dart';
import 'today_strip.dart';

/// Sidebar on the left, a top bar with today's figures, the bell and the
/// signed-in user, and the selected screen beneath.
///
/// Laid out after an operations dashboard: the frame is a shade off the
/// canvas and the screens sit in it as panels. The sidebar keeps its
/// labels -- office staff should never have to learn an icon to find a
/// page -- and folds to icons only on request.
class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _selectedIndex = 0;
  bool _collapsed = false;
  late final NotificationProvider _notifications;

  @override
  void initState() {
    super.initState();
    // Lives with the shell: polling starts at sign-in and stops at sign-out.
    _notifications = NotificationProvider(
      NotificationRepository(context.read<ApiClient>()),
    );
  }

  @override
  void dispose() {
    _notifications.dispose();
    super.dispose();
  }

  // Screen and sidebar entry declared together, so inserting a module can
  // never point a notification at the wrong page.
  //
  // Grouped by the office's job: what is happening today, money and the
  // camera checks that protect it, and the setup that changes rarely.
  // Labels are the screens' titles word for word, in the office's words;
  // the technical term (YOLOv8) is on the screen, not in the menu.
  static const _modules = <_Module>[
    _Module('Overview', Icons.map_outlined, Icons.map, FleetMapScreen(), group: 'Today'),
    _Module('Trips', Icons.departure_board_outlined, Icons.departure_board,
        TripMonitorScreen()),
    _Module('Van Status Board', Icons.view_list_outlined, Icons.view_list, VanBoardScreen()),
    _Module('Review Starts', Icons.rule_outlined, Icons.rule, StartReviewScreen(), managerOnly: true),
    _Module('Special Trips', Icons.alt_route_outlined, Icons.alt_route,
        DispatchBoardScreen(), managerOnly: true),
    _Module('Emergencies (SOS)', Icons.emergency_outlined, Icons.emergency,
        SosConsoleScreen(), urgent: true),
    _Module('Messages', Icons.chat_bubble_outline, Icons.chat_bubble, MessagesScreen()),
    _Module('Remittance', Icons.receipt_long_outlined, Icons.receipt_long, RemittanceScreen(),
        group: 'Money & checks'),
    _Module('Disputes', Icons.gavel_outlined, Icons.gavel, DisputesScreen()),
    _Module('Boarding Audit', Icons.how_to_reg_outlined, Icons.how_to_reg, BoardingAuditScreen(),
        managerOnly: true),
    _Module('Driving Flags', Icons.speed_outlined, Icons.speed, DrivingFlagsScreen()),
    _Module('Fares & Cash', Icons.payments_outlined, Icons.payments, RevenueScreen()),
    _Module('Passenger Count Checks', Icons.fact_check_outlined, Icons.fact_check,
        AuditDashboardScreen(), managerOnly: true),
    // Member Records opens the group: the Cashier sees it, so the heading
    // must not sit on an entry the Cashier is not shown.
    _Module('Member Records', Icons.airport_shuttle_outlined, Icons.airport_shuttle,
        FleetRosterScreen(), group: 'Setup'),
    _Module('Phones', Icons.phone_android_outlined, Icons.phone_android, PhonesScreen()),
    _Module('Timetable', Icons.calendar_month_outlined, Icons.calendar_month,
        ScheduleScreen(), managerOnly: true),
    _Module('Rules & Settings', Icons.tune_outlined, Icons.tune, PolicyEditorScreen(),
        managerOnly: true),
  ];

  /// The pages this person may open. The Cashier records payments and
  /// does not decide what is owed, set rules or plan the timetable (brief
  /// section 3), so those pages are not offered rather than refused.
  List<_Module> get _visible {
    final isManager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    return [for (final m in _modules) if (isManager || !m.managerOnly) m];
  }

  /// Looked up by screen type rather than written out as an index. False
  /// when this person is not shown that page.
  bool _show(bool Function(Widget) test) {
    final index = _visible.indexWhere((m) => test(m.screen));
    if (index >= 0) setState(() => _selectedIndex = index);
    return index >= 0;
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
      'unconfirmed_trip_start' => _show((w) => w is StartReviewScreen) || _show((w) => w is TripMonitorScreen),
      _ when n.isTripAlert => _show((w) => w is TripMonitorScreen),
      _ => _show((w) => w is AuditDashboardScreen),
    };
  }

  void _openToday(TodayTarget target) => switch (target) {
        TodayTarget.fleet => _show((w) => w is FleetMapScreen),
        TodayTarget.trips => _show((w) => w is TripMonitorScreen),
        TodayTarget.checks => _show((w) => w is AuditDashboardScreen),
        TodayTarget.emergencies => _show((w) => w is SosConsoleScreen),
      };

  @override
  Widget build(BuildContext context) {
    final modules = _visible;
    return ChangeNotifierProvider<NotificationProvider>.value(
      value: _notifications,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Row(
          children: [
            _Sidebar(
              modules: modules,
              selectedIndex: _selectedIndex,
              collapsed: _collapsed,
              onSelect: (i) => setState(() => _selectedIndex = i),
              onToggle: () => setState(() => _collapsed = !_collapsed),
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    strip: TodayStrip(onOpen: _openToday),
                    bell: NotificationBell(onOpen: _openFor),
                  ),
                  Expanded(child: modules[_selectedIndex].screen),
                ],
              ),
            ),
          ],
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
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: strip),
          const SizedBox(width: AppSpacing.md),
          const _AppearanceButton(),
          bell,
          const SizedBox(width: AppSpacing.sm),
          const _ProfileMenu(),
        ],
      ),
    );
  }
}

/// Sun or moon: the palette the console is *not* in, so the icon says
/// what a click will do.
class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<Appearance>();
    final dark = appearance.isDark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: appearance.toggle,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          color: AppColors.textMuted),
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
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: TextStyle(color: AppColors.onFill, fontWeight: FontWeight.w800),
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
                  Text('Cooperative office', style: text.bodySmall),
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
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.modules,
    required this.selectedIndex,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
  });

  final List<_Module> modules;
  final int selectedIndex;
  final bool collapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : AppDuration.normal,
      curve: Curves.easeOut,
      width: collapsed ? 76 : 256,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The mark is black ink on transparent and is drawn only on a
          // light surface, so it sits on a light plate -- the reference
          // dashboard's logo tile.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
            child: BrandPlate(height: collapsed ? 24 : 44),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Text('Cooperative office console', style: text.bodySmall),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (var i = 0; i < modules.length; i++) ...[
                  if (modules[i].group != null)
                    collapsed
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.md, horizontal: AppSpacing.md),
                            child: Divider(),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
                            child: Text(modules[i].group!.toUpperCase(), style: text.labelSmall),
                          ),
                  _SidebarItem(
                    module: modules[i],
                    selected: i == selectedIndex,
                    collapsed: collapsed,
                    onTap: () => onSelect(i),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
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

/// One entry. Selection is carried three ways -- light fill, dark bold
/// label, filled icon -- so it never rests on hue alone (WCAG 1.4.1). The
/// SOS entry keeps a red icon in every state and a red fill when open: it
/// is the one page that is an alarm, and should look like one.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.module,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _Module module;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = module.urgent ? AppColors.danger : AppColors.primary;
    final iconColour = selected
        ? AppColors.onFill
        : (module.urgent ? AppColors.danger : AppColors.textMuted);
    final row = Row(
      mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(selected ? module.selectedIcon : module.icon, size: 20, color: iconColour),
        if (!collapsed) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              module.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.onFill : AppColors.textPrimary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
    final item = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: collapsed ? module.label : null,
        child: Material(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            hoverColor: AppColors.surfaceSunken,
            onTap: onTap,
            child: SizedBox(
              height: AppSizing.minTouchTarget - 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
    // Folded to icons, the name is still one hover away.
    return collapsed
        ? Tooltip(message: module.label, preferBelow: false, child: item)
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
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          height: AppSizing.minTouchTarget - 4,
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (!collapsed) const SizedBox(width: AppSpacing.md),
              Icon(icon, size: 20, color: AppColors.textMuted),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.md),
                Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One sidebar entry and the screen it shows.
class _Module {
  const _Module(this.label, this.icon, this.selectedIcon, this.screen,
      {this.group, this.urgent = false, this.managerOnly = false});

  /// The sidebar label -- and, word for word, the screen's own title.
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  /// Heading drawn above this entry; it opens a new group.
  final String? group;

  /// Drawn in the danger colour. Only the SOS console.
  final bool urgent;

  /// Hidden from the Cashier; the Terminal Manager's decisions.
  final bool managerOnly;
}
