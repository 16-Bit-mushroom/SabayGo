import 'package:flutter/material.dart';

import '../tokens.dart';

/// A modal bottom sheet with a title, a handle and a way out.
///
/// Three sheets each built their own: one had a grab handle and no close
/// button, one a close button and no handle, one neither — so on the third
/// the only way back was the system gesture. A sheet that can only be
/// dismissed by dragging is a dead end for anyone using a switch or a
/// keyboard, and dragging is not discoverable for anyone else.
///
/// Also handles the keyboard. `viewInsets` padding is why the terminal
/// search field is not covered by the very keyboard it summons.
///
/// Pass a scrollable [child] for a long sheet: it is given the remaining
/// height up to [maxHeightFactor] of the screen, so a list fills the sheet
/// while a short column keeps the sheet short.
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.title,
    required this.child,
    this.subtitle,
    this.maxHeightFactor = 0.9,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * maxHeightFactor,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decorative: the close button is the operable control, and
                // announcing a handle would leave a reader hunting for a
                // drag gesture it cannot perform.
                ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(
                      top: AppSpacing.md,
                      bottom: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xl,
                    right: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(title, style: text.titleLarge),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(subtitle!, style: text.bodySmall),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
