import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class DriverPassengerCard extends StatelessWidget {
  final String name;
  final String rating;
  final String rides;
  final String pickupNode;
  final String dropoffNode;

  const DriverPassengerCard({
    Key? key,
    required this.name,
    required this.rating,
    required this.rides,
    required this.pickupNode,
    required this.dropoffNode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const CircleAvatar(radius: 20, backgroundColor: Colors.transparent, child: Icon(Icons.person, color: Colors.deepPurple)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 12),
                    const SizedBox(width: 4),
                    Text(rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(" · $rides rides", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                // Upgraded Routing Display
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(pickupNode, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: AppColors.success),
                    const SizedBox(width: 8),
                    Text(dropoffNode, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}