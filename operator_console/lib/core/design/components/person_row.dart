import 'package:flutter/material.dart';

import '../tokens.dart';

/// A person on a trip: initial, name, and their role underneath -- the
/// crew rows on the Overview card and the Trips page.
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.role, required this.name});

  final String role;

  /// Null when nobody is assigned; said in words, not left blank.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryContainer,
          child: Text(
            (name ?? '?').characters.first.toUpperCase(),
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name ?? 'Not assigned', overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              Text(role, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
