import 'package:flutter/material.dart';

import '../tokens.dart';

/// A screen whose data did not load: the server's own message and one way
/// forward. Was a private `_buildError` copied into every screen.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.danger, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text('Could not load this page', style: text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing to show yet -- said plainly, with what makes something appear.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;

  /// What would put something here ("Create trips from the Timetable").
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textMuted, size: 36),
              const SizedBox(height: AppSpacing.md),
              Text(title, textAlign: TextAlign.center, style: text.titleSmall),
              if (hint != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(hint!, textAlign: TextAlign.center, style: text.bodySmall),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
