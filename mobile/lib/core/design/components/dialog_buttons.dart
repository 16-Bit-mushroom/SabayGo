import 'package:flutter/material.dart';

import '../tokens.dart';

/// The two buttons at the foot of a dialog: the action, and under it the
/// way out, the same width and height and lined up edge to edge.
///
/// The theme makes a filled button full width, so in a plain [AlertDialog]
/// the action took a line of its own and the way out was left as small text
/// at the right edge above it, lined up with nothing (20 Nov). Stacked, the
/// pair keeps one shape at every screen width and text size. The action is
/// on top and the way out at the bottom, where a thumb lands first, so a
/// stray tap leaves things as they were.
///
/// Pass it as the dialog's only action: `actions: [DialogButtons(...)]`.
///
/// Each button carries both labels, the other one invisible and silent to
/// a screen reader: both buttons are laid out to the same width, so they
/// wrap alike and come out the same height even when one label needs two
/// lines (a small phone, large text). A test therefore finds a label twice:
/// find the button by type inside the dialog, not by its text.
class DialogButtons extends StatelessWidget {
  const DialogButtons({
    super.key,
    required this.action,
    required this.onAction,
    this.cancel = 'Cancel',
    this.onCancel,
    this.danger = false,
    this.busy = false,
  });

  /// What the action says: "End shift", "Sign out", "Save".
  final String action;

  /// Null while the action cannot be taken yet (a reason not typed in):
  /// the button shows disabled.
  final VoidCallback? onAction;

  /// What the way out says: "Stay", "Not yet", "Keep it".
  final String cancel;

  /// Closes the dialog with no answer when left out.
  final VoidCallback? onCancel;

  /// A step that cannot be taken back (cancelling a reservation, deleting a
  /// message or the account): the action is red.
  final bool danger;

  /// The action is running: a spinner over its label, and neither button
  /// takes a tap until it finishes.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: busy ? null : onAction,
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.onFill)
              : null,
          child: _label(action, spinner: busy),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: busy ? null : (onCancel ?? () => Navigator.pop(context)),
          child: _label(cancel),
        ),
      ],
    );
  }

  Widget _label(String own, {bool spinner = false}) => Stack(
        alignment: Alignment.center,
        children: [
          for (final text in {action, cancel})
            Opacity(
              opacity: text == own && !spinner ? 1 : 0,
              // The copy that only sizes the button stays out of what a
              // screen reader hears; the button's own label stays in it,
              // also while the spinner covers it.
              alwaysIncludeSemantics: text == own,
              child: Text(text, textAlign: TextAlign.center),
            ),
          if (spinner)
            SizedBox.square(
              dimension: 20,
              // On the disabled grey, in the colour the button had.
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: danger ? AppColors.danger : AppColors.primary),
            ),
        ],
      );
}
