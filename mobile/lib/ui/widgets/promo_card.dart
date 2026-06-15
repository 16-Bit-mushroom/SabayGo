import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PromoCard extends StatelessWidget {
  final String code;
  final String description;
  final bool isApplied;
  final VoidCallback onTap;

  const PromoCard({
    Key? key,
    required this.code,
    required this.description,
    required this.isApplied,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isApplied ? AppColors.success.withOpacity(0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isApplied ? AppColors.success : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.local_offer_outlined, color: isApplied ? AppColors.success : AppColors.textSecondary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            if (isApplied)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 4),
                  Text("Applied", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                ],
              )
          ],
        ),
      ),
    );
  }
}