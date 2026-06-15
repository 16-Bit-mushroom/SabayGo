import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../widgets/request_timer_ring.dart';
import '../widgets/request_stat_card.dart';
import '../widgets/request_route_details.dart';

class RideRequestScreen extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const RideRequestScreen({
    Key? key,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C), // Darker background to match the map overlay mockup
      body: Stack(
        children: [
          // 1. Map Background (Placeholder)
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Container(color: AppColors.highlight), // Frosty blue map tint
            ),
          ),

          // 2. Top Header (Request Title & Timer)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("NEW RIDE REQUEST", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      SizedBox(height: 4),
                      Text("Accept or Decline", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const RequestTimerRing(secondsLeft: 10, progress: 0.8), // Static mock for now
                ],
              ),
            ),
          ),

          // 3. Bottom Sheet Decision Area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pull Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),

                    // Stats Row
                    Row(
                      children: const [
                        RequestStatCard(icon: Icons.location_on_outlined, iconColor: Colors.deepPurple, value: "1.2", label: "km away"),
                        RequestStatCard(icon: Icons.payments_outlined, iconColor: AppColors.success, value: "₱180", label: "total fare", valueColor: AppColors.success),
                        RequestStatCard(icon: Icons.group_outlined, iconColor: Colors.blueGrey, value: "2", label: "seats req."),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Fixed Route Details
                    const RequestRouteDetails(
                      passengerName: "Alex Johnson", 
                      passengerRating: "4.9",        
                      pickupNode: "Matina Node",
                      dropoffNode: "Ulas Node",
                      totalDistance: "8.4 km total",
                      estTime: "~22 min",
                    ),
                    const SizedBox(height: 32),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onDecline,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.red.shade200),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: Colors.red.shade50,
                            ),
                            child: const Text("Decline", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onAccept,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppColors.success,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Accept Ride", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      
      // FIXED: Injected the global driver navigation bar
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0, // 'Home' Map view is active
        selectedItemColor: AppColors.success, // Swapped to green to match the Driver's primary action color
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