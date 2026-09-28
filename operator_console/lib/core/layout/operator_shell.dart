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
import '../../viewmodels/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/notification_repository.dart';
import '../../viewmodels/notification_provider.dart';
import 'notification_bell.dart';

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
  static const _modules = <_Module>[
    _Module('Revenue', Icons.payments_outlined, Icons.payments, RevenueScreen()),
    _Module('Trip Dispatcher', Icons.route_outlined, Icons.route,
        DispatchBoardScreen()),
    _Module('Live Fleet', Icons.my_location_outlined, Icons.my_location,
        FleetMapScreen()),
    _Module('Schedules', Icons.calendar_month_outlined, Icons.calendar_month,
        ScheduleScreen()),
    _Module('Fleet & Crew', Icons.directions_car_outlined, Icons.directions_car,
        FleetRosterScreen()),
    _Module('Policies', Icons.tune_outlined, Icons.tune, PolicyEditorScreen()),
    _Module('YOLOv8 Audits', Icons.policy_outlined, Icons.policy,
        AuditDashboardScreen()),
    _Module('Emergency (SOS)', Icons.emergency_outlined, Icons.emergency,
        SosConsoleScreen()),
    _Module('Messages', Icons.chat_bubble_outline, Icons.chat_bubble,
        MessagesScreen()),
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
          // ==========================================
          // PERSISTENT SIDEBAR NAVIGATION
          // ==========================================
          NavigationRail(
            backgroundColor: const Color(0xFF2E3440), // Nord Dark Canvas
            unselectedIconTheme: const IconThemeData(color: Colors.white54),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
            selectedIconTheme: const IconThemeData(color: Color(0xFF88C0D0)), // Nord Blue Accent
            selectedLabelTextStyle: const TextStyle(color: Color(0xFF88C0D0), fontWeight: FontWeight.bold),
            indicatorColor: Colors.transparent,
            extended: true, // Forces labels to show next to icons
            minExtendedWidth: 240,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.only(top: 32.0, bottom: 16.0),
              child: Column(
                children: [
                  const Text(
                    'SABAYGO\nCOMMAND',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  NotificationBell(onOpen: _openFor),
                ],
              ),
            ),
            destinations: [
              for (final m in _modules)
                NavigationRailDestination(
                  icon: Icon(m.icon),
                  selectedIcon: Icon(m.selectedIcon),
                  label: Text(m.label),
                ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Consumer<AuthProvider>(
                  builder: (context, auth, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 12),
                    child: Column(
                      children: [
                        Text(
                          auth.profile?.displayName ?? auth.profile?.email ?? '',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => auth.signOut(),
                          icon: const Icon(Icons.logout, size: 16, color: Colors.white54),
                          label: const Text('Sign Out',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          const VerticalDivider(thickness: 1, width: 1, color: Colors.black12),
          
          // ==========================================
          // MAIN CONTENT AREA
          // ==========================================
          Expanded(
            child: _modules[_selectedIndex].screen,
          ),
        ],
      ),
      ),
    );
  }
}

/// One sidebar entry and the screen it shows.
class _Module {
  const _Module(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}
