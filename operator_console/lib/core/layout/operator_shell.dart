import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/ai_audit_queue/screens/audit_dashboard_screen.dart';
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
import '../design/components/brand_logo.dart';
import '../design/tokens.dart';
import 'notification_bell.dart';
import 'profile_dialog.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _selectedIndex = 0;
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

  // Screen and rail entry declared together. They used to be two lists
  // indexed by the same integer, with the audit tab's position written out
  // as a constant -- inserting a module in the middle silently pointed the
  // variance alert at the wrong tab.
  //
  // Grouped by the office's job rather than listed flat: nine peers in one
  // column is a list to read, three labelled groups is a place to look
  // (chunking; Law of Common Region). Live operations first, because that
  // is what changes minute to minute. Order is free to change --
  // notifications find their tab by screen type, not by index.
  static const _modules = <_Module>[
    _Module('Live Fleet', Icons.my_location_outlined, Icons.my_location,
        FleetMapScreen(), group: 'Operations'),
    _Module('Trips', Icons.departure_board_outlined, Icons.departure_board,
        TripMonitorScreen()),
    _Module('Trip Dispatcher', Icons.route_outlined, Icons.route,
        DispatchBoardScreen()),
    _Module('Emergency (SOS)', Icons.emergency_outlined, Icons.emergency,
        SosConsoleScreen(), urgent: true),
    _Module('Messages', Icons.chat_bubble_outline, Icons.chat_bubble,
        MessagesScreen()),
    _Module('Revenue', Icons.payments_outlined, Icons.payments,
        RevenueScreen(), group: 'Oversight'),
    _Module('YOLOv8 Audits', Icons.policy_outlined, Icons.policy,
        AuditDashboardScreen()),
    _Module('Schedules', Icons.calendar_month_outlined, Icons.calendar_month,
        ScheduleScreen(), group: 'Setup'),
    _Module('Fleet & Crew', Icons.directions_car_outlined, Icons.directions_car,
        FleetRosterScreen()),
    _Module('Policies', Icons.tune_outlined, Icons.tune, PolicyEditorScreen()),
  ];

  /// Where a notification lands when the office clicks it. Looked up by
  /// screen type rather than written out as a constant -- the two
  /// parallel lists this replaced sent a variance alert to whichever
  /// module happened to sit at index 5.
  int _indexOfScreen(bool Function(Widget) test) =>
      _modules.indexWhere((m) => test(m.screen));

  void _openFor(AppNotification n) {
    final index = n.isSosAlert
        ? _indexOfScreen((w) => w is SosConsoleScreen)
        : _indexOfScreen((w) => w is AuditDashboardScreen);
    if (index >= 0) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NotificationProvider>.value(
      value: _notifications,
      child: Scaffold(
        body: Row(
          children: [
            _Sidebar(
              modules: _modules,
              selectedIndex: _selectedIndex,
              onSelect: (i) => setState(() => _selectedIndex = i),
              bell: NotificationBell(onOpen: _openFor),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _modules[_selectedIndex].screen),
          ],
        ),
      ),
    );
  }
}

/// The console's navigation: logo, bell, grouped modules, signed-in user.
///
/// A custom column rather than [NavigationRail], which has no notion of
/// group headings. Light like the content it frames -- the old Nord rail
/// was the darkest thing on screen, which made navigation the loudest
/// element on a page whose job is the data beside it.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.modules,
    required this.selectedIndex,
    required this.onSelect,
    required this.bell,
  });

  final List<_Module> modules;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget bell;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 248,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xl, AppSpacing.sm, AppSpacing.xs),
            child: Row(
              children: [
                const BrandLogo(height: 52),
                const Spacer(),
                bell,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('Cooperative office', style: text.bodySmall),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (var i = 0; i < modules.length; i++) ...[
                  if (modules[i].group != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                          AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
                      child: Text(modules[i].group!.toUpperCase(),
                          style: text.labelSmall),
                    ),
                  _SidebarItem(
                    module: modules[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final name =
                  auth.profile?.displayName ?? auth.profile?.email ?? '';
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
                child: Row(
                  children: [
                    // Avatar and name together are the way into "My
                    // profile" -- where people look for their own account.
                    Expanded(
                      child: Tooltip(
                        message: 'My profile',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => const ProfileDialog(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.primaryContainer,
                                  child: Text(
                                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                                    style: const TextStyle(
                                        color: AppColors.primary, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall!
                                        .copyWith(color: AppColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: auth.signOut,
                      icon: const Icon(Icons.logout,
                          size: 18, color: AppColors.textMuted),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One row. Selection is carried three ways -- ink fill, white bold label,
/// filled icon -- so it never rests on hue alone (WCAG 1.4.1). The SOS
/// entry keeps a red icon in every state and a red fill when open: it is
/// the one module that is an alarm, and should look like one.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.module,
    required this.selected,
    required this.onTap,
  });

  final _Module module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = module.urgent ? AppColors.danger : AppColors.primary;
    final iconColour = selected
        ? Colors.white
        : (module.urgent ? AppColors.danger : AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            hoverColor: AppColors.surfaceSunken,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  Icon(selected ? module.selectedIcon : module.icon,
                      size: 20, color: iconColour),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      module.label,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One sidebar entry and the screen it shows.
class _Module {
  const _Module(this.label, this.icon, this.selectedIcon, this.screen,
      {this.group, this.urgent = false});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  /// Heading drawn above this entry; it opens a new group.
  final String? group;

  /// Drawn in the danger colour. Only the SOS console.
  final bool urgent;
}
