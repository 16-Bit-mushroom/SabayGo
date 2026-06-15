import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class DriverProfileHeader extends StatelessWidget {
  final String driverName;
  final String rating;
  final String tripsCount;
  final String vehicleModel;
  final String vehicleColor; // <-- Added this
  final String plateNumber;

  const DriverProfileHeader({
    Key? key,
    required this.driverName,
    required this.rating,
    required this.tripsCount,
    required this.vehicleModel,
    required this.vehicleColor, // <-- Added this
    required this.plateNumber,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar with Verified Badge
        Stack(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primaryAction.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, size: 40, color: AppColors.primaryAction),
            ),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        
        // Driver Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driverName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    rating,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    " · $tripsCount trips",
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "Top Rated Driver",
                  style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        
        // Updated Vehicle Info Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceHover,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_car, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(vehicleModel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              // Injected the color here so it reads cleanly
              Text(vehicleColor, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(plateNumber, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}