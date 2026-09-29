import 'package:flutter/material.dart';

import '../tokens.dart';

/// A tappable row that holds one answer: a terminal, a date, a time.
///
/// Anatomy, once. A marker on the left, a quiet label above the answer, and
/// a hint on the right that this row opens something. The search form asks
/// three questions and each row was previously built by hand, so the "From"
/// field, the "To" field and the date button had three different heights,
/// two different label styles and no shared idea of what an unanswered
/// question looks like.
///
/// An unanswered row shows [placeholder] rather than nothing. A blank row
/// reads as broken; "Choose a terminal" reads as a turn to take.
class AppPickerRow extends StatelessWidget {
  const AppPickerRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.semanticHint,
    super.key,
  });

  /// The marker: a [JourneyMarker], an icon. Kept narrow so labels align.
  final Widget leading;

  final String label;

  /// Null when the question has not been answered yet.
  final String? value;
  final String placeholder;

  final VoidCallback onTap;

  /// What tapping does, for a screen reader: "Opens the terminal list".
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final answered = value != null;

    return Semantics(
      button: true,
      label: '$label: ${answered ? value! : 'not chosen'}',
      hint: semanticHint,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // Comfortably past the 48dp floor: this is the control someone
          // taps while walking to a terminal.
          constraints: const BoxConstraints(
            minHeight: AppSizing.minTouchTarget + AppSpacing.sm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                SizedBox(width: leadingWidth, child: Center(child: leading)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: text.labelSmall),
                      const SizedBox(height: 2),
                      Text(
                        answered ? value! : placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: answered
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.unfold_more,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Width of the marker column. Exposed so a divider between two rows can
  /// be indented to start where the text starts, which is what makes the
  /// markers read as one rail rather than two dots.
  static const double leadingWidth = 16;
}
