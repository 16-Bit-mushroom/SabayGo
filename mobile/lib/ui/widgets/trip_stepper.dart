import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TripStepper extends StatelessWidget {
  final List<String> nodes;
  final int currentIndex;

  const TripStepper({
    Key? key,
    required this.nodes,
    required this.currentIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(nodes.length * 2 - 1, (index) {
        // Build the connecting lines
        if (index % 2 != 0) {
          int lineIndex = index ~/ 2;
          bool isPassed = lineIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 4,
              color: isPassed ? AppColors.success : Colors.grey.shade300,
            ),
          );
        }

        // Build the Node Circles
        int nodeIndex = index ~/ 2;
        bool isPassed = nodeIndex < currentIndex;
        bool isCurrent = nodeIndex == currentIndex;

        return Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isPassed ? AppColors.success : (isCurrent ? AppColors.primaryAction : Colors.grey.shade300),
                shape: BoxShape.circle,
                border: isCurrent ? Border.all(color: AppColors.highlight, width: 4) : null,
              ),
              child: isPassed ? const Icon(Icons.check, size: 14, color: AppColors.surface) : null,
            ),
            const SizedBox(height: 8),
            Text(
              nodes[nodeIndex],
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isPassed || isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        );
      }),
    );
  }
}