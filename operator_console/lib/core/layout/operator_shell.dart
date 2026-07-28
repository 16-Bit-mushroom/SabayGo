import 'package:flutter/material.dart';
import '../../modules/ai_audit_queue/screens/audit_dashboard_screen.dart';
import '../../modules/trip_dispatcher/screens/dispatch_board_screen.dart';
import '../../modules/fleet_management/screens/fleet_roster_screen.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _selectedIndex = 0;

  // The array of operational modules
  final List<Widget> _modules = [
    const AuditDashboardScreen(),
    const DispatchBoardScreen(),
    const FleetRosterScreen(),
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
                icon: Icon(Icons.policy_outlined),
                selectedIcon: Icon(Icons.policy),
                label: Text('YOLOv8 Audits'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: Text('Trip Dispatcher'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.directions_car_outlined),
                selectedIcon: Icon(Icons.directions_car),
                label: Text('Fleet & Crew'),
              ),
            ],
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