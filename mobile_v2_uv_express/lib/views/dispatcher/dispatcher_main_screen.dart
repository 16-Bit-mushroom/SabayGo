import 'package:flutter/material.dart';
import 'dispatcher_dashboard_screen.dart';
import 'trip_schedule_screen.dart';
import 'log_book_screen.dart';

class DispatcherMainScreen extends StatefulWidget {
  const DispatcherMainScreen({super.key});

  @override
  State<DispatcherMainScreen> createState() => _DispatcherMainScreenState();
}

class _DispatcherMainScreenState extends State<DispatcherMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DispatcherDashboardScreen(),
    const TripScheduleScreen(),
    const LogBookScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2059),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RDT Transport', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Dispatcher Portal', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              // TODO: Dispatcher Profile
            },
          )
        ],
      ),
      body: _screens[_currentIndex],
      
      // --- Right-Docked Floating Action Button ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Open QR Scanner Camera
        },
        backgroundColor: const Color(0xFF00A859),
        elevation: 4,
        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
        label: const Text('Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      
      // --- Standard 3-Tab Bottom Navigation ---
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF00A859).withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF00A859)),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month, color: Color(0xFF00A859)),
            label: 'Schedules',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: Color(0xFF00A859)),
            label: 'Log Book',
          ),
        ],
      ),
    );
  }
}