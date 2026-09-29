import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../viewmodels/home_search_viewmodel.dart';

/// Narrows the results to a part of the day.
///
/// The bar was a `SizedBox(height: 40)`, which clipped its own chips the
/// moment the system font was enlarged — the control for filtering a list
/// became unreadable for the people most likely to need a shorter list. It
/// is now sized by its content, so it grows with the text.
///
/// Selection is carried by fill, border and label weight together, never by
/// colour alone (WCAG 1.4.1).
class TimeBlockFilterBar extends StatelessWidget {
  const TimeBlockFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TimeBlock selected;
  final ValueChanged<TimeBlock> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        children: [
          for (final block in TimeBlock.values) ...[
            _Chip(
              label: block.label,
              isSelected: block == selected,
              onTap: () => onSelected(block),
            ),
            if (block != TimeBlock.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      // The label already says what is selected, and the tick shifts the
      // width of every chip as the selection moves along the row.
      showCheckmark: false,
      backgroundColor: AppColors.surfaceRaised,
      selectedColor: AppColors.primary,
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
        color: isSelected ? Colors.white : AppColors.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2,
      ),
    );
  }
}
