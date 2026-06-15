import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PremiumComparisonTable extends StatelessWidget {
  const PremiumComparisonTable({Key? key}) : super(key: key);

  TableRow _buildRow(String feature, String freeVal, String premiumVal, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isHeader ? Colors.transparent : Colors.grey.shade200)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Text(
            feature,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.normal : FontWeight.bold,
              color: isHeader ? AppColors.textSecondary : AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            freeVal,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isHeader ? AppColors.textSecondary : Colors.grey.shade400,
              fontSize: 12,
              fontWeight: freeVal == "Yes" ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Container(
          color: isHeader ? Colors.deepPurple : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            premiumVal,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isHeader ? Colors.white : (premiumVal == "Never" ? Colors.deepPurple : AppColors.success),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.2),
          },
          children: [
            _buildRow("Feature", "Free", "Commute+", isHeader: true),
            _buildRow("Ad-free", "✗", "✓"),
            _buildRow("Priority matching", "✗", "✓"),
            _buildRow("Surge pricing", "Yes", "Never"),
            _buildRow("Premium drivers", "✗", "✓"),
          ],
        ),
      ),
    );
  }
}