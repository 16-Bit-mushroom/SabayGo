import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class PaymentMethodTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget leadingIcon;
  final bool isSelected;
  final VoidCallback onTap;

  const PaymentMethodTile({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Ink(
      // Applies a subtle 8% opacity tint of your primary Nord color when selected
      color: isSelected ? AppColors.primaryAction.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(child: leadingIcon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16, 
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary, 
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? AppColors.primaryAction : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}