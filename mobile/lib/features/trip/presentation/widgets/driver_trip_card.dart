import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class DriverTripCard extends StatelessWidget {
  final String passengerName;
  final String origin;
  final String destination;
  final String dateTime;
  final String fare;
  final String? tip;
  final bool isShared;
  final bool isCompleted;

  const DriverTripCard({
    Key? key,
    required this.passengerName,
    required this.origin,
    required this.destination,
    required this.dateTime,
    required this.fare,
    this.tip,
    this.isShared = true,
    this.isCompleted = true,
  }) : super(key: key);

  Widget _buildPill(String label, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 10, color: color), const SizedBox(width: 2)],
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), shape: BoxShape.circle),
            child: const CircleAvatar(radius: 18, backgroundColor: Colors.transparent, child: Icon(Icons.person, color: Colors.deepPurple, size: 20)),
          ),
          const SizedBox(width: 12),
          
          // Trip Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(passengerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(origin, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.diamond, size: 8, color: AppColors.success),
                    const SizedBox(width: 6),
                    Expanded(child: Text(destination, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(dateTime, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    const SizedBox(width: 8),
                    if (isShared) _buildPill("Shared", Colors.deepPurple, null),
                    const SizedBox(width: 4),
                    _buildPill(isCompleted ? "Done" : "Cancelled", isCompleted ? AppColors.success : Colors.red, isCompleted ? Icons.check : Icons.close),
                  ],
                )
              ],
            ),
          ),
          
          // Earnings Details
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fare, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isCompleted ? AppColors.success : AppColors.textSecondary)),
              if (tip != null && isCompleted) ...[
                const SizedBox(height: 4),
                Text("+$tip tip", style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ]
            ],
          )
        ],
      ),
    );
  }
}