import 'package:flutter/material.dart';

import '../tokens.dart';

/// The app's one surface.
///
/// Before this, eleven screens drew their own container: four with a drop
/// shadow, three with a saturated fill, two with `Colors.grey.shade200`,
/// and every one of them with its own radius. Shadows and tinted fills were
/// doing the work that space and a hairline should do — a page of floating
/// shadowed boxes reads as busy however carefully each box is made.
///
/// So: white, one hairline, one radius, and generous padding. Depth comes
/// from the card being lighter than the scaffold, which is the whole reason
/// [AppColors.surface] is not white.
///
/// [onTap] puts the ink inside the clip, which a `Card` wrapped in an
/// `InkWell` does not — the splash squares off the rounded corners.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// One sentence describing the whole card, for a tappable row whose parts
  /// would otherwise be read out one fragment at a time.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    Widget surface = Material(
      color: AppColors.surfaceRaised,
      borderRadius: radius,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(padding: padding, child: child),
            ),
    );

    surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: AppColors.divider),
      ),
      child: surface,
    );

    if (semanticLabel == null) return surface;
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: surface,
    );
  }
}
