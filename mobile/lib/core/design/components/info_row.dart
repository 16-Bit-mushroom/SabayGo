import 'package:flutter/material.dart';

import '../tokens.dart';

/// One labelled fact: passenger, fare, plate number.
///
/// Reads as a receipt line — quiet label on the left, the fact itself set
/// heavier on the right. The value is what someone came to read, so it
/// carries the weight; the label only says what it is.
///
/// Both sides flex. The old hand-rolled version put the label in an
/// unbounded `Row` and the value in an `Expanded`, so at a large text scale
/// a long terminal name pushed the label off its own row.
class AppInfoRow extends StatelessWidget {
  const AppInfoRow({
    required this.label,
    required this.value,
    this.valueWidget,
    super.key,
  });

  final String label;

  /// Also the screen-reader text, so pass the readable form rather than a
  /// glyph. Ignored when [valueWidget] is given, except by the reader.
  final String value;

  /// For a value that is not plain text — [Money], a chip, a link.
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: text.bodyMedium!.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: text.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
