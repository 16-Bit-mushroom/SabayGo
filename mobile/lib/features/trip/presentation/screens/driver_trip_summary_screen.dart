import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/fare_breakdown_card.dart';

class DriverTripSummaryScreen extends StatelessWidget {
  final VoidCallback onFindNextRide;
  final VoidCallback onGoOffline;

  const DriverTripSummaryScreen({
    Key? key,
    required this.onFindNextRide,
    required this.onGoOffline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // 1. The Scrollable Content
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              // Success Animation / Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 80),
              ),
              const SizedBox(height: 24),

              // Header
              const Text("Trip Completed!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                "You've successfully dropped off Sarah K.", 
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)
              ),
              const SizedBox(height: 40),

              // Earnings Breakdown
              const FareBreakdownCard(
                baseFare: "₱ 50.00",
                distanceFare: "₱ 45.00",
                discount: "-₱ 41.80",
                serviceFee: "-₱ 5.32", 
                total: "₱ 47.88",      
              ),
            ],
          ),
        ),
      ),
      
      // 2. Fixed Bottom Buttons
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Keeps it tight to the bottom
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onFindNextRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Find Next Ride", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: TextButton(
                  onPressed: onGoOffline,
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Go Offline", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}