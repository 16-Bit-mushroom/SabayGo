import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/ai_audit_queue/screens/audit_dashboard_screen.dart';
import '../../modules/trip_dispatcher/screens/dispatch_board_screen.dart';
import '../../modules/fleet_management/screens/fleet_roster_screen.dart';
import '../../modules/schedule_management/screens/schedule_screen.dart';
import '../../modules/policy_editor/screens/policy_editor_screen.dart';
import '../../modules/revenue/screens/revenue_screen.dart';
import '../../viewmodels/auth_provider.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _selectedIndex = 0;

  // The array of operational modules
  final List<Widget> _modules = [
    const RevenueScreen(),
    const DispatchBoardScreen(),
    const ScheduleScreen(),
    const FleetRosterScreen(),
    const PolicyEditorScreen(),
    const AuditDashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Text(
                'SABAYGO\nCOMMAND',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.0,
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments),
                label: Text('Revenue'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: Text('Trip Dispatcher'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: Text('Schedules'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.directions_car_outlined),
                selectedIcon: Icon(Icons.directions_car),
                label: Text('Fleet & Crew'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: Text('Policies'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.policy_outlined),
                selectedIcon: Icon(Icons.policy),
                label: Text('YOLOv8 Audits'),
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
            child: _modules[_selectedIndex],
          ),
        ],
      ),
    );
  }
}