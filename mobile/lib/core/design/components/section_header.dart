import 'package:flutter/material.dart';

import '../tokens.dart';

/// A heading inside a screen, with somewhere for an action to live.
///
/// Marked as a heading so a screen-reader user can move between the
/// sections of a long screen instead of reading it top to bottom. Every
/// screen had headings; none of them were headings to the accessibility
/// tree, which made the boarding pass and the reservations list one
/// undifferentiated run of text.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(
    this.title, {
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// A text button, usually. Sits on the baseline of the title.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: text.titleMedium),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppSpacing.sm),
          action!,
        ],
      ],
    );
  }
}
