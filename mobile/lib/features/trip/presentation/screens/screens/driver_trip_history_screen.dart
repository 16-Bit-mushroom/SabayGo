import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../../widgets/driver_trip_summary_row.dart';
import '../../widgets/driver_trip_filter_bar.dart';
import '../../widgets/driver_trip_card.dart';

class DriverTripHistoryScreen extends StatelessWidget {
  final bool isFilterExpanded;
  final VoidCallback onToggleFilter;
  final String activeFilter;
  final Function(String) onSelectFilter;

  const DriverTripHistoryScreen({
    Key? key,
    required this.isFilterExpanded,
    required this.onToggleFilter,
    required this.activeFilter,
    required this.onSelectFilter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("My Trip History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppColors.textPrimary)),
        automaticallyImplyLeading: false, 
        elevation: 0,
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          const DriverTripSummaryRow(trips: "6", passengers: "13", earned: "₱1,455", avgFare: "₱243"),
          const SizedBox(height: 24),
          DriverTripFilterBar(
            isFilterExpanded: isFilterExpanded,
            onToggleFilter: onToggleFilter,
            activeFilter: activeFilter,
            onSelectFilter: onSelectFilter,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                DriverTripCard(
                  passengerName: "Sarah K.",
                  origin: "Matina Node",
                  destination: "SM City Ecoland",
                  dateTime: "Jun 11, 2026 · 9:14 AM",
                  fare: "₱200",
                  tip: "₱20",
                  isShared: true,
                ),
                DriverTripCard(
                  passengerName: "Dev P.",
                  origin: "Ulas Node",
                  destination: "Bangkal Hub",
                  dateTime: "Jun 11, 2026 · 11:30 AM",
                  fare: "₱120",
                  isShared: false,
                ),
                DriverTripCard(
                  passengerName: "Grace T.",
                  origin: "Roxas Ave",
                  destination: "Toril",
                  dateTime: "Jun 11, 2026 · 1:45 PM",
                  fare: "₱0",
                  isCompleted: false,
                  isShared: true,
                ),
                DriverTripCard(
                  passengerName: "Mia C. +3",
                  origin: "Bangkal Hub",
                  destination: "Matina Node",
                  dateTime: "Jun 10, 2026 · 5:20 PM",
                  fare: "₱280",
                  tip: "₱40",
                  isShared: true,
                ),
              ],
            ),
          ),
        ],
      ),
      
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 1, // 'Trips' tab
        selectedItemColor: AppColors.success, // Driver theme
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}