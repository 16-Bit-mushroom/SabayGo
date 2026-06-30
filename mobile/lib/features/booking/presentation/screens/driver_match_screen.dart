import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/widgets/quick_action_buttons.dart';
import '../widgets/driver_profile_header.dart';

class DriverMatchScreen extends StatefulWidget {
  final String driverName;
  final String vehicleModel;
  final String plateNumber;
  final String vehicleColor;
  final String rating;
  // REMOVED: currentPaymentId and onChangePayment
  final VoidCallback onBackPressed;
  final VoidCallback onMessageDriver;
  final VoidCallback onCallDriver;
  final VoidCallback onCancelRide;
  final VoidCallback onStartRide;

  const DriverMatchScreen({
    Key? key,
    required this.driverName,
    required this.vehicleModel,
    required this.plateNumber,
    required this.vehicleColor,
    required this.rating,
    required this.onBackPressed,
    required this.onMessageDriver,
    required this.onCallDriver,
    required this.onCancelRide,
    required this.onStartRide,
  }) : super(key: key);

  @override
  State<DriverMatchScreen> createState() => _DriverMatchScreenState();
}

class _DriverMatchScreenState extends State<DriverMatchScreen> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. BACKGROUND
          Positioned.fill(
            child: Container(
              color: AppColors.highlight.withOpacity(0.2),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        FloatingActionButton.small(
                          onPressed: widget.onBackPressed,
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
                        ),
                      ],
                    ),
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
            height: _isExpanded ? 360.0 : 90.0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THE TAPPABLE HEADER AREA
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.near_me, color: Colors.deepPurple, size: 20),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Driver is 2 mins away", style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(_isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: Colors.grey, size: 28),
                        ],
                      ),
                    ),
                  ),

                  // THE CONTENT
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).padding.bottom + 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DriverProfileHeader(
                            driverName: widget.driverName,
                            rating: widget.rating,
                            tripsCount: "1,247",
                            vehicleModel: widget.vehicleModel,
                            vehicleColor: widget.vehicleColor,
                            plateNumber: widget.plateNumber,
                          ),
                          const SizedBox(height: 16),

                          // NEW: Replaced Payment method with Cost-Share Info
                          
                          // const SizedBox(height: 24),

                          QuickActionButtons(
                            onMessage: widget.onMessageDriver,
                            onCall: widget.onCallDriver,
                            onCancel: widget.onCancelRide,
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: widget.onStartRide,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D2059),
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
            ),
          ),
        ],
      ),
    );
  }
}