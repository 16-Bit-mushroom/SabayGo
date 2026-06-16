import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/booking/viewmodels/driver_viewmodel.dart';
import '../widgets/navigation_header.dart';
import '../widgets/driver_passenger_card.dart';
import '../widgets/co_passenger_card.dart'; 
import '../widgets/trip_stepper.dart'; 

class DriverNavigationScreen extends StatefulWidget {
  final DriverStep currentStep;
  final VoidCallback onMainAction; 
  final VoidCallback onMessage;
  final VoidCallback onCall;

  const DriverNavigationScreen({
    Key? key,
    required this.currentStep,
    required this.onMainAction,
    required this.onMessage,
    required this.onCall,
  }) : super(key: key);

  @override
  State<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

class _DriverNavigationScreenState extends State<DriverNavigationScreen> {
  // Local state to track if the sheet is open or closed
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    String statusText = "Heading to Pickup Point";
    Color statusColor = Colors.deepPurple;
    String buttonText = "Slide to Arrive at Pickup →";
    IconData buttonIcon = Icons.near_me;
    int stepIndex = 0;

    if (widget.currentStep == DriverStep.arrivedAtPickup) {
      statusText = "Waiting for Passenger";
      statusColor = Colors.orange;
      buttonText = "Passenger Boarded: Start Ride →";
      buttonIcon = Icons.directions_car;
      stepIndex = 1;
    } else if (widget.currentStep == DriverStep.inRide) {
      statusText = "Heading to Drop-off";
      statusColor = AppColors.success;
      buttonText = "Complete & Process Payment";
      buttonIcon = Icons.payments;
      stepIndex = 3;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Map Background
          Positioned.fill(
            child: Container(color: AppColors.highlight.withOpacity(0.2)),
          ),
          
          // 2. Top Navigation Header
          const Positioned(
            top: 0, left: 0, right: 0,
            child: NavigationHeader(
              distance: "200 m",
              instruction: "Turn Right on McArthur Hwy",
              totalDistanceLeft: "200",
            ),
          ),

          // 3. Floating Minimalist Trip Stepper
          Positioned(
            top: 130, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: TripStepper(
                nodes: const ["Toril", "Matina", "SM City", "Ulas"],
                currentIndex: stepIndex, 
              ),
            ),
          ),

          // 4. Floating ETA Widget
          Positioned(
            right: 16,
            top: 240, 
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

          // 5. Tap-to-Expand Bottom Sheet
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
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
                      // Pull Handle
                      Center(
                        child: Column(
                          children: [
                            Icon(_isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: Colors.grey, size: 24),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      
                      // Status Banner (Always Visible)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 10, color: statusColor),
                            const SizedBox(width: 8),
                            Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      
                      // Collapsible Content
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: !_isExpanded 
                          ? const SizedBox(height: 16) // Just a little spacing when closed
                          : Column(
                              children: [
                                const SizedBox(height: 16),
                                const DriverPassengerCard(
                                  name: "Sarah K.",
                                  rating: "4.8",
                                  pickupNode: "Toril Node",
                                  dropoffNode: "Ulas Node",
                                ),
                                const SizedBox(height: 16),

                                SizedBox(
                                  height: 60,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    children: const [
                                      CoPassengerCard(name: "Mark D.", destinationNode: "SM City Ecoland"),
                                      CoPassengerCard(name: "Chloe S.", destinationNode: "Matina Node"),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: widget.onMessage,
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
                                        onPressed: widget.onCall,
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
                                const SizedBox(height: 16),
                              ],
                            ),
                      ),

                      // Main Action Button (Always Visible)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: widget.currentStep == DriverStep.inRide
                            ? ElevatedButton.icon(
                                onPressed: widget.onMainAction,
                                icon: Icon(buttonIcon, color: AppColors.surface),
                                label: Text(buttonText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.surface)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              )
                            : InkWell(
                                onTap: widget.onMainAction, 
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      Center(child: Text(buttonText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                      Container(
                                        margin: const EdgeInsets.all(4),
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                        child: Icon(buttonIcon, color: statusColor),
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
          ),
        ],
      ),
    );
  }
}