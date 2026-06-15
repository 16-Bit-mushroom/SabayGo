import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../widgets/trip_stepper.dart';
import '../widgets/co_passenger_card.dart';
import '../widgets/fare_breakdown_card.dart';

class InRideScreen extends StatelessWidget {
  final VoidCallback onSosPressed;
  final VoidCallback onBackPressed;

  const InRideScreen({
    Key? key,
    required this.onSosPressed,
    required this.onBackPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 1. Top Half: Map & Floating Controls
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: Stack(
              children: [
                // Mock Map Background
                Container(color: AppColors.highlight.withOpacity(0.2)),
                
                // Top Action Bar
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FloatingActionButton.small(
                          heroTag: "back_btn",
                          onPressed: onBackPressed,
                          backgroundColor: AppColors.surface,
                          child: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 16),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryAction,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                          ),
                          child: const Text("Arriving at 9:24 AM · 6 min", style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        FloatingActionButton.extended(
                          heroTag: "sos_btn",
                          onPressed: onSosPressed,
                          backgroundColor: Colors.red.shade50,
                          elevation: 2,
                          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                          label: const Text("SOS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Map Marker Placeholder
                const Center(child: Icon(Icons.my_location, color: AppColors.primaryAction, size: 32)),
              ],
            ),
          ),

          // 2. Bottom Half: Scrollable Data
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  // Stepper Component
                  const TripStepper(
                    nodes: ["Matina", "Bangkal", "Ulas", "Toril"], // Capstone context
                    currentIndex: 2, // Currently at Ulas
                  ),
                  const SizedBox(height: 32),

                  // Co-Passengers
                  const Text("Co-Passengers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 60,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: const [
                        CoPassengerCard(name: "Sarah K.", destinationNode: "Ulas Node"),
                        CoPassengerCard(name: "Dev P.", destinationNode: "Toril Node"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Fare Breakdown
                  const FareBreakdownCard(
                    baseFare: "₱ 50.00",
                    distanceFare: "₱ 45.00",
                    discount: "-₱ 41.80",
                    serviceFee: "₱ 10.00",
                    total: "₱ 53.20",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // Bottom Nav
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 1, // 'Trips' tab is active
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