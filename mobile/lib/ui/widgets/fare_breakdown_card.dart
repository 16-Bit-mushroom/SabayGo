import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FareBreakdownCard extends StatelessWidget {
  final String baseFare;
  final String distanceFare;
  final String discount;
  final String serviceFee; // <-- Added Service Fee
  final String total;

  const FareBreakdownCard({
    Key? key,
    required this.baseFare,
    required this.distanceFare,
    required this.discount,
    required this.serviceFee, // <-- Added Service Fee
    required this.total,
  }) : super(key: key);

  Widget _buildRow(String label, String amount, {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label, 
            style: TextStyle(
              color: isTotal ? AppColors.textPrimary : AppColors.textSecondary, 
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, 
              fontSize: isTotal ? 16 : 14
            )
          ),
          Text(
            amount, 
            style: TextStyle(
              color: isDiscount ? AppColors.success : (isTotal ? AppColors.primaryAction : AppColors.textPrimary), 
              fontWeight: isTotal || isDiscount ? FontWeight.bold : FontWeight.normal, 
              fontSize: isTotal ? 18 : 14
            )
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Fare Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Row(
                  children: const [
                    Icon(Icons.eco, size: 12, color: AppColors.success),
                    SizedBox(width: 4),
                    Text("Eco ride", style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRow("Base fare", baseFare),
          _buildRow("Distance (5.2 km)", distanceFare),
          _buildRow("Shared discount (44%)", discount, isDiscount: true),
          _buildRow("Service fee", serviceFee), // <-- Rendered here
          const Divider(height: 24),
          _buildRow("Total", total, isTotal: true),
        ],
      ),
    );
  }
}