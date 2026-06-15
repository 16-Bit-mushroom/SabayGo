import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class CoPassengerCard extends StatelessWidget {
  final String name;
  final String destinationNode;

  const CoPassengerCard({
    Key? key,
    required this.name,
    required this.destinationNode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      // FIX 1: Changed from .all(12) to .symmetric to reduce vertical pressure
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // FIX 2: Explicitly set a smaller radius for the avatar
          CircleAvatar(
            radius: 16, 
            backgroundColor: AppColors.primaryAction.withOpacity(0.1),
            child: const Icon(Icons.person, size: 18, color: AppColors.primaryAction),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), 
                  overflow: TextOverflow.ellipsis
                ),
                const SizedBox(height: 2), // Reduced internal spacing
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 10, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        destinationNode, 
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), 
                        overflow: TextOverflow.ellipsis
                      )
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}