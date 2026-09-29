import 'package:flutter/material.dart';

/// A peso amount.
///
/// Exists for one reason: figures that change must not make the layout
/// jump. Roboto's default figures are proportional, so "₱1,180" is
/// narrower than "₱1,880" and a fare that updates after a reschedule
/// visibly shifts the column it sits in. Tabular figures are the same
/// width, and a right-aligned money column stays a column.
///
/// Precision is a caller's decision because the two uses differ. A results
/// list is scanned, so it shows whole pesos; a receipt states what was
/// actually charged, to the centavo. Both go through [format] so no screen
/// invents a third convention.
class Money extends StatelessWidget {
  const Money(
    this.amount, {
    this.style,
    this.showCentavos = true,
    super.key,
  });

  final double amount;
  final TextStyle? style;
  final bool showCentavos;

  static String format(double amount, {bool showCentavos = true}) =>
      '₱${amount.toStringAsFixed(showCentavos ? 2 : 0)}';

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      format(amount, showCentavos: showCentavos),
      style: base.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
