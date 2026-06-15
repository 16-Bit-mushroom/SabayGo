import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class DriverTripSummaryRow extends StatelessWidget {
  final String trips;
  final String passengers;
  final String earned;
  final String avgFare;

  const DriverTripSummaryRow({
    Key? key,
    required this.trips,
    required this.passengers,
    required this.earned,
    required this.avgFare,
  }) : super(key: key);

  Widget _buildCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          _buildCard(trips, "Trips", Colors.deepPurple),
          _buildCard(passengers, "Passengers", AppColors.success),
          _buildCard(earned, "Earned", AppColors.success), // Darker green in mockup, using success base
          _buildCard(avgFare, "Avg Fare", Colors.orange),
        ],
      ),
    );
  }
}