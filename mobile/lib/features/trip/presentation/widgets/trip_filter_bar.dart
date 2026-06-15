import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class TripFilterBar extends StatelessWidget {
  final bool isFilterExpanded;
  final VoidCallback onToggleFilter;
  final String activeFilter;
  final Function(String) onSelectFilter;

  const TripFilterBar({
    Key? key,
    required this.isFilterExpanded,
    required this.onToggleFilter,
    required this.activeFilter,
    required this.onSelectFilter,
  }) : super(key: key);

  Widget _buildChip(String label, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () => onSelectFilter(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.surface : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: const [
                      Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                      SizedBox(width: 12),
                      Text("Search trips...", style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: onToggleFilter,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: isFilterExpanded ? Colors.deepPurple.withOpacity(0.1) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isFilterExpanded ? Colors.deepPurple : Colors.grey.shade300),
                  ),
                  child: Icon(Icons.filter_alt_outlined, color: isFilterExpanded ? Colors.deepPurple : AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (isFilterExpanded) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip("All", isSelected: activeFilter == "All"),
                _buildChip("Completed", isSelected: activeFilter == "Completed"),
                _buildChip("Cancelled", isSelected: activeFilter == "Cancelled"),
                _buildChip("Eco", isSelected: activeFilter == "Eco"),
                _buildChip("Solo", isSelected: activeFilter == "Solo"),
              ],
            ),
          ]
        ],
      ),
    );
  }
}