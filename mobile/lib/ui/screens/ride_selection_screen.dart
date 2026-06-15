import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../widgets/ride_option_card.dart';

class RideSelectionScreen extends StatelessWidget {
  // In a real MVVM setup, these values and callbacks are passed in from the ViewModel.
  // We mock them here so the UI compiles and is testable today.
  final VoidCallback onBackPressed;
  final Function(String) onRideSelected;
  final String selectedRideId;

  const RideSelectionScreen({
    Key? key,
    required this.onBackPressed,
    required this.onRideSelected,
    this.selectedRideId = 'eco_1', // Default selection state
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Top Half: The Map Placeholder
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.55,
            child: Container(
              color: AppColors.highlight.withOpacity(0.2), // Light frosty blue mock map
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      // Map App Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FloatingActionButton.small(
                            onPressed: onBackPressed,
                            backgroundColor: AppColors.surface,
                            elevation: 2,
                            child: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 16),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "Distance\n5.2 km",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          )
                        ],
                      ),
                      // Mock Markers (Using your corridor data)
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: const Text("📍 Matina Node, Origin"), backgroundColor: AppColors.surface),
                      ),
                      const SizedBox(height: 40),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Chip(label: const Text("🏁 Ulas Node, Dest"), backgroundColor: AppColors.surface),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Bottom Half: Ride Selection Card/Sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.50,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
                ],
              ),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Choose your ride",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Select a flat-rate corridor option",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  
                  // Ride Options List
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        RideOptionCard(
                          title: "SabayGo Solo",
                          subtitle: "Private ride, zero detours",
                          price: "PHP 180.00",
                          timeEst: "14 min",
                          passengerRatio: "1/4",
                          isSelected: selectedRideId == 'solo_1',
                          onTap: () => onRideSelected('solo_1'),
                        ),
                        RideOptionCard(
                          title: "SabayGo Shared",
                          subtitle: "Cost-share with 1 commuter",
                          price: "PHP 90.00",
                          timeEst: "16 min",
                          passengerRatio: "2/4",
                          isSelected: selectedRideId == 'eco_1',
                          onTap: () => onRideSelected('eco_1'),
                        ),
                      ],
                    ),
                  ),
                  
                  // The Action Button (Tells ViewModel to execute Booking)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                         // Action passes to ViewModel here
                         print("Calling ViewModel to reserve seat via NAHGM API...");
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAction,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        "Confirm Ride",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.surface),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primaryAction,
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