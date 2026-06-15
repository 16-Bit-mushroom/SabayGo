import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ProfileKpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const ProfileKpiCard({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}