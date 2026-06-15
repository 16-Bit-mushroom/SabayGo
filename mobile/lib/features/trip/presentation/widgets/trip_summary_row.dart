import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class TripSummaryRow extends StatelessWidget {
  final String totalSpent;
  final String totalSaved;
  final String ecoRides;

  const TripSummaryRow({
    Key? key,
    required this.totalSpent,
    required this.totalSaved,
    required this.ecoRides,
  }) : super(key: key);

  Widget _buildCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0), // slightly less padding to account for inner margins
      child: Row(
        children: [
          _buildCard(totalSpent, "Total Spent", Colors.deepPurple),
          _buildCard(totalSaved, "Total Saved", AppColors.success),
          _buildCard(ecoRides, "Eco Rides", AppColors.success),
        ],
      ),
    );
  }
}