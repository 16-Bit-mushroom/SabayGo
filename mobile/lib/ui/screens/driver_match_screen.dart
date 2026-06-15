import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../widgets/driver_profile_header.dart';
import '../widgets/quick_action_buttons.dart';

class DriverMatchScreen extends StatelessWidget {
  // ViewModel Callbacks
  final VoidCallback onBackPressed;
  final VoidCallback onMessageDriver;
  final VoidCallback onCallDriver;
  final VoidCallback onCancelRide;
  final VoidCallback onStartRide;

  const DriverMatchScreen({
    Key? key,
    required this.onBackPressed,
    required this.onMessageDriver,
    required this.onCallDriver,
    required this.onCancelRide,
    required this.onStartRide,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. The Map Placeholder Background
          Positioned.fill(
            child: Container(
              color: AppColors.highlight.withOpacity(0.2), // Light frosty blue map
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        FloatingActionButton.small(
                          onPressed: onBackPressed,
                          backgroundColor: AppColors.surface,
                          elevation: 2,
                          child: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 16),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.circle, color: AppColors.success, size: 10),
                              SizedBox(width: 8),
                              Text("Live tracking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. The Bottom Sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
              ),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Hugs the content tightly since we removed the redundant cards
                children: [
                  // Status Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.near_me, color: Colors.deepPurple),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Driver is 2 mins away", style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("Marcus is heading your way", style: TextStyle(color: Colors.deepPurple, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Clean Driver Profile (Redundant cards removed)
                  const DriverProfileHeader(
                    driverName: "Marcus Williams",
                    rating: "4.9",
                    tripsCount: "1,247",
                    vehicleModel: "Tesla Model 3",
                    vehicleColor: "Pearl White",
                    plateNumber: "GHI-4892",
                  ),
                  const SizedBox(height: 24),

                  // Quick Actions
                  QuickActionButtons(
                    onMessage: onMessageDriver,
                    onCall: onCallDriver,
                    onCancel: onCancelRide,
                  ),
                  const SizedBox(height: 24),

                  // Primary Action
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onStartRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple, // Matches the theme of your screenshot
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text("Start Ride", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.surface)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, color: AppColors.surface, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // Standard Bottom Nav
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
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