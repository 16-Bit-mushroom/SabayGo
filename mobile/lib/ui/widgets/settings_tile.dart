import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final bool showArrow;
  final VoidCallback onTap;

  const SettingsTile({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
    this.showArrow = true,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
            ),
            if (trailing != null) trailing!,
            if (trailing != null && showArrow) const SizedBox(width: 8),
            if (showArrow) const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}