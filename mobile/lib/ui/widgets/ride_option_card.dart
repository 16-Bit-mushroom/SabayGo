import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class RideOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final String timeEst;
  final String passengerRatio;
  final bool isSelected;
  final VoidCallback onTap;

  const RideOptionCard({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.timeEst,
    required this.passengerRatio,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isSelected ? AppColors.primaryAction : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primaryAction.withOpacity(0.1), blurRadius: 8)]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Side: Icon & Details
            Row(
              children: [
                Icon(
                  Icons.directions_car, 
                  color: isSelected ? AppColors.primaryAction : AppColors.textSecondary,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          timeEst,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.group, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          passengerRatio,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // Right Side: Price
            Text(
              price,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}