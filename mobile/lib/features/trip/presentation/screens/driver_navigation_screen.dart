import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/navigation_header.dart';
import '../widgets/driver_passenger_card.dart';

class DriverNavigationScreen extends StatelessWidget {
  final bool isArrived;
  final VoidCallback onSwipeToArrive;
  final VoidCallback onCompleteTrip;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  const DriverNavigationScreen({
    Key? key,
    required this.isArrived,
    required this.onSwipeToArrive,
    required this.onCompleteTrip,
    required this.onMessage,
    required this.onCall,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Map Background
          Positioned.fill(
            child: Container(color: AppColors.highlight.withOpacity(0.2)),
          ),

          // 2. The Navigation Header
          const Positioned(
            top: 0, left: 0, right: 0,
            child: NavigationHeader(
              distance: "200 m",
              instruction: "Turn Right on McArthur Hwy",
              totalDistanceLeft: "200",
            ),
          ),

          // 3. Floating ETA Widget (Speedometer removed)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height * 0.45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Column(
                children: const [
                  Text("8 min", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("ETA", style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ),

          // 4. Bottom Sheet Action Area
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isArrived ? AppColors.success.withOpacity(0.1) : Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: isArrived ? AppColors.success : Colors.deepPurple),
                          const SizedBox(width: 8),
                          Text(
                            isArrived ? "Trip Complete!" : "Heading to Pickup Point",
                            style: TextStyle(color: isArrived ? AppColors.success : Colors.deepPurple, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Passenger Info
                    const DriverPassengerCard(
                      name: "Sarah Kim",
                      rating: "4.8",
                      rides: "83",
                      pickupNode: "Matina Node",
                      dropoffNode: "SM City Ecoland",
                    ),
                    const SizedBox(height: 16),

                    // Quick Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onMessage,
                            icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.deepPurple),
                            label: const Text("Message", style: TextStyle(color: Colors.deepPurple)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.deepPurple.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onCall,
                            icon: const Icon(Icons.phone_outlined, size: 18, color: AppColors.success),
                            label: const Text("Call", style: TextStyle(color: AppColors.success)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: AppColors.success.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Main Action Button (Toggles based on state)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: isArrived
                          ? ElevatedButton.icon(
                              onPressed: onCompleteTrip,
                              icon: const Icon(Icons.check, color: AppColors.success),
                              label: const Text("Trip Completed!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.success)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success.withOpacity(0.1),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.success)),
                              ),
                            )
                          : InkWell(
                              onTap: onSwipeToArrive, 
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    const Center(child: Text("Slide to Arrive at Pickup →", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                    Container(
                                      margin: const EdgeInsets.all(4),
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                      child: const Icon(Icons.near_me, color: Colors.deepPurple),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      
      // FIXED: Restored the Bottom Navigation Bar
     
    );
  }
}