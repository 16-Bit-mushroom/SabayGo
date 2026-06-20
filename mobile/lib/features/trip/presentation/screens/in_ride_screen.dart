import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/trip_stepper.dart';
import '../widgets/co_passenger_card.dart';
import '../widgets/fare_breakdown_card.dart';

class InRideScreen extends StatefulWidget {
  final VoidCallback onSosPressed;
  final VoidCallback onBackPressed;
  final VoidCallback onSimulateDropoff;

  const InRideScreen({
    Key? key,
    required this.onSosPressed,
    required this.onBackPressed,
    required this.onSimulateDropoff,
  }) : super(key: key);

  @override
  State<InRideScreen> createState() => _InRideScreenState();
}

class _InRideScreenState extends State<InRideScreen> {
  bool _isExpanded = true; // Card starts open

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. BACKGROUND: Full Screen Map & Floating Controls
          Positioned.fill(
            child: Container(
              color: AppColors.highlight.withOpacity(0.2), // Mock Map Background
              child: Stack(
                children: [
                  // Top Action Bar
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FloatingActionButton.small(
                            heroTag: "back_btn",
                            onPressed: widget.onBackPressed,
                            backgroundColor: AppColors.surface,
                            elevation: 2,
                            child: const Icon(
                              Icons.arrow_back_ios_new,
                              color: AppColors.textPrimary,
                              size: 16,
                            ),
                          ),
                          // The Secret Presentation Trigger
                          GestureDetector(
                            onTap: widget.onSimulateDropoff,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryAction,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 8),
                                ],
                              ),
                              child: const Text(
                                "Arriving at 9:24 AM · 6 min",
                                style: TextStyle(
                                  color: AppColors.surface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          FloatingActionButton.extended(
                            heroTag: "sos_btn",
                            onPressed: widget.onSosPressed,
                            backgroundColor: Colors.red.shade50,
                            elevation: 2,
                            icon: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red,
                              size: 18,
                            ),
                            label: const Text(
                              "SOS",
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Map Marker Placeholder
                  const Center(
                    child: Icon(
                      Icons.my_location,
                      color: AppColors.primaryAction,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. FOREGROUND: Tap-to-Slide Animated Sheet
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: 0,
            left: 0,
            right: 0,
            // Fixed height: 480px when open, 90px (just the header) when closed
            height: _isExpanded ? 480.0 : 90.0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THE TAPPABLE HEADER AREA
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Trip Details",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            color: Colors.grey,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // THE CONTENT (Wrapped to prevent overflow)
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      // Dynamic bottom padding to respect the device bezel
                      padding: EdgeInsets.fromLTRB(
                          24, 0, 24, MediaQuery.of(context).padding.bottom + 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stepper Component
                          const TripStepper(
                            nodes: [
                              "Matina",
                              "Bangkal",
                              "Ulas",
                              "Toril",
                            ],
                            currentIndex: 2, 
                          ),
                          const SizedBox(height: 32),

                          // Co-Passengers
                          const Text(
                            "Co-Passengers",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 60,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: const [
                                CoPassengerCard(
                                  name: "Sarah K.",
                                  destinationNode: "Ulas Node",
                                ),
                                CoPassengerCard(
                                  name: "Dev P.",
                                  destinationNode: "Toril Node",
                                ),
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
            ),
          ),
        ],
      ),
    );
  }
}