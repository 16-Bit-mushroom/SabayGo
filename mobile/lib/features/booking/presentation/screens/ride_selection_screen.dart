import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/ride_option_card.dart';

class RideSelectionScreen extends StatefulWidget {
  final VoidCallback onConfirmRide;
  final VoidCallback onBackPressed;
  final Function(String) onRideSelected;
  final String selectedRideId;

  const RideSelectionScreen({
    Key? key,
    required this.onConfirmRide,
    required this.onBackPressed,
    required this.onRideSelected,
    this.selectedRideId = '',
  }) : super(key: key);

  @override
  State<RideSelectionScreen> createState() => _RideSelectionScreenState();
}

class _RideSelectionScreenState extends State<RideSelectionScreen> {
  bool _isExpanded = true; // Starts open

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. BACKGROUND: Full Screen Map
          Positioned.fill(
            child: Container(
              color: AppColors.highlight.withOpacity(0.2),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: [
                      Row(
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(color: Colors.black12, blurRadius: 4),
                              ],
                            ),
                            child: const Text(
                              "Distance\n5.2 km",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          label: const Text("📍 Matina Node, Origin"),
                          backgroundColor: AppColors.surface,
                        ),
                      ),
                      const SizedBox(height: 80),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Chip(
                          label: const Text("🏁 Ulas Node, Dest"),
                          backgroundColor: AppColors.surface,
                        ),
                      ),
                    ],
                  ),
                ),
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
            // 55% height when open, ~100px when closed (just the header)
            height: _isExpanded ? 420.0 : 90.0,
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
                            "Choose your ride",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
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

                  // THE CONTENT (Wrapped to prevent overflow when animating)
                  Expanded(
                    child: SingleChildScrollView(
                      physics:
                          const NeverScrollableScrollPhysics(), // Disables inner scrolling to keep it clean
                      padding: EdgeInsets.fromLTRB(
                        24,
                        0,
                        24,
                        MediaQuery.of(context).padding.bottom + 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Select a flat-rate corridor option",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          RideOptionCard(
                            title: "Solo",
                            subtitle: "Private ride, zero detours",
                            price: "PHP 180.00",
                            timeEst: "14 min",
                            passengerRatio: "1/4",
                            isSelected: widget.selectedRideId == 'solo_1',
                            onTap: () => widget.onRideSelected('solo_1'),
                          ),
                          RideOptionCard(
                            title: "Shared",
                            subtitle: "Cost-share with 1 commuter",
                            price: "PHP 90.00",
                            timeEst: "16 min",
                            passengerRatio: "2/4",
                            isSelected: widget.selectedRideId == 'eco_1',
                            onTap: () => widget.onRideSelected('eco_1'),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: widget.onConfirmRide,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.selectedRideId.isEmpty
                                    ? Colors.grey.shade400
                                    : AppColors.primaryAction,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Confirm Ride",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
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
