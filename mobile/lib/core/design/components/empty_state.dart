import 'package:flutter/material.dart';

import '../tokens.dart';

/// Nothing-to-show, and what to do about it.
///
/// Promoted from `home_search/home_screen.dart`, which had the only decent
/// version of this in the app. Ten screens show an empty or failed state;
/// the rest inline a centred `Text` and so lose the two things that make an
/// empty state useful — a title that says which situation this is, and an
/// action when one exists.
///
/// It fills the viewport and stays scrollable so a `RefreshIndicator` above
/// it still works: an empty list is the most likely moment for someone to
/// pull to refresh, and a non-scrollable child silently swallows the
/// gesture.
///
/// [title] is marked as a heading so screen-reader users can jump to it and
/// hear what state the screen is in rather than hunting through the body.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          // minHeight, not a fixed height: at a large text scale the content
          // is taller than the viewport and a fixed box would clip it.
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.section,
                vertical: AppSpacing.xxl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The icon repeats the title; it is atmosphere, not
                  // information.
                  ExcludeSemantics(
                    child: Icon(icon, size: 48, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.titleLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium!
                        .copyWith(color: AppColors.textMuted, height: 1.5),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
