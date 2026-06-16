import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/request_timer_ring.dart';
import '../widgets/request_stat_card.dart';
import '../widgets/request_route_details.dart';

class RideRequestScreen extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const RideRequestScreen({
    Key? key,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  // Starts expanded so the driver sees all info immediately
  bool _isExpanded = true;

  void _showDeclineConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Decline Request?", style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text("Are you sure you want to pass on this ride request? Declining too many rides may affect your acceptance rate."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Keep Request", style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                widget.onDecline();           // Trigger the decline action
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, elevation: 0),
              child: const Text("Yes, Decline", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

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

          // 3. Tap-to-Expand Bottom Sheet Decision Area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
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

                      // Collapsible Content (Stats and Route)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: !_isExpanded 
                          ? const SizedBox(height: 8) // Minimal spacing when collapsed
                          : Column(
                              children: [
                                // Stats Row
                                Row(
                                  children: const [
                                    RequestStatCard(icon: Icons.location_on_outlined, iconColor: Colors.deepPurple, value: "1.2", label: "km away"),
                                    RequestStatCard(icon: Icons.payments_outlined, iconColor: AppColors.success, value: "₱53", label: "est. fare", valueColor: AppColors.success),
                                    RequestStatCard(icon: Icons.group_outlined, iconColor: Colors.blueGrey, value: "1", label: "seat req."),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Route Details
                                const RequestRouteDetails(
                                  passengerName: "Sarah K.", 
                                  passengerRating: "4.8",        
                                  pickupNode: "Toril Node",
                                  dropoffNode: "Ulas Node",
                                  totalDistance: "5.2 km total",
                                  estTime: "~12 min",
                                ),
                                const SizedBox(height: 32),
                              ],
                            ),
                      ),

                      // Action Buttons (Always Visible!)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _showDeclineConfirmation(context),
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
                              onPressed: widget.onAccept,
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
          ),
        ],
      ),
    );
  }
}