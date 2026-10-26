import 'package:flutter/material.dart';

import '../tokens.dart';

/// The top of every screen: what it is called, one plain sentence on what
/// it is for, and the screen's own buttons on the right.
///
/// Every screen used to build this row by hand -- three title sizes, a
/// Refresh that was an icon on one screen and a text button on the next,
/// and titles that did not match the sidebar ("Trip Dispatch Command"
/// under "Trip Dispatcher"). The title here should read exactly as the
/// sidebar entry does, so staff know they landed where they clicked.
///
/// [description] is written for someone new to the office: what they can
/// do here, in their words, not the system's.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String description;

  final List<Widget> actions;

  /// A step inside a page (Setup's Terminals, Timetable, ...): the title a
  /// size down, under the page's own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? AppSpacing.lg : AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The office's words only: system and table names belong to
                // the code and the manuscript, not the page (UI redesign v3).
                // A heading to a screen reader, so a page can be found by
                // its title.
                Semantics(
                  header: true,
                  child: Text(title, style: compact ? text.titleLarge : text.headlineMedium),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(description, style: text.bodyMedium!.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The Refresh button every data screen carries, the same everywhere.
class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key, required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
      );
}
