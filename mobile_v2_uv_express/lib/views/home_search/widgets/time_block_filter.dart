import 'package:flutter/material.dart';
import '../../../viewmodels/home_search_viewmodel.dart';

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
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: TimeBlock.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final block = TimeBlock.values[index];
          final isSelected = block == selected;
          return ChoiceChip(
            label: Text(block.label),
            selected: isSelected,
            onSelected: (_) => onSelected(block),
          );
        },
      ),
    );
  }
}
