import 'package:flutter/material.dart';

import '../tokens.dart';

/// A rounded card, optionally with a heading row: icon, title, and one
/// control at the right (the reference dashboard's tile).
///
/// Replaces a private `_Panel` / `Card(...)` written separately in most
/// screens, each with its own radius and border.
///
/// [fill] makes the body take the remaining height -- for a panel placed
/// in an `Expanded` whose body is a list. Leave it off inside a scroll
/// view, where there is no remaining height to take.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.fill = false,
    this.color = AppColors.surfaceRaised,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heading = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(child: Text(title!, style: text.titleSmall)),
                ?trailing,
              ],
            ),
          );
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: heading == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: [heading, fill ? Expanded(child: child) : child],
            ),
    );
  }
}

/// One figure in a tile: a small label, a big number, an optional line
/// under it. The revenue totals, a trip's counts, the overview card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color = AppColors.textPrimary,
    this.caption,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Colour of the figure. Pick the status colour that matches the label's
  /// meaning; the label always says it in words too.
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis, style: text.labelMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}
