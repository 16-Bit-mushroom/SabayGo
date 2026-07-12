import 'package:flutter/material.dart';
import 'dispatcher_dashboard_screen.dart';
import 'trip_schedule_screen.dart';
import 'manage_fleet_screen.dart';
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
    const ManageFleetScreen(),
    const LogBookScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2059),
        elevation: 0, // Removed shadow for a flatter, modern look
        title: Row(
          children: [
            // Added a subtle terminal icon to make the header pop
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Explicitly set text color to white for readability
                Text(
                  'RDT Transport', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white, letterSpacing: 0.5),
                ),
                Text(
                  'Dispatcher Portal', 
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () {
              // TODO: Dispatcher Profile
            },
          ),
          const SizedBox(width: 8), // Padding on the right
        ],
      ),
      body: _screens[_currentIndex],
      
      // --- Conditionally render the FAB ONLY on the Dashboard (Index 0) ---
      floatingActionButton: _currentIndex == 0 
          ? FloatingActionButton.extended(
              onPressed: () {
                // TODO: Open QR Scanner Camera
              },
              backgroundColor: const Color(0xFF00A859),
              elevation: 4,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: const Text('Scan QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null, // Hides the button on all other tabs
      
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      
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
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car, color: Color(0xFF00A859)),
            label: 'Vans',
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