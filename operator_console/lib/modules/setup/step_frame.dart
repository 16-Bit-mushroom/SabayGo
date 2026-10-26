import 'package:flutter/material.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';

/// One Setup step: its heading, then the step's records beside the panel
/// that adds or shows one. Records are entered here, not in a dialog, so a
/// first-day set-up never leaves the page.
///
/// Wide enough, the list and the side panel sit side by side; narrower,
/// the side panel comes first and the list follows at a fixed height.
class StepFrame extends StatelessWidget {
  const StepFrame({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    required this.list,
    this.side,
  });

  final String title;
  final String description;
  final List<Widget> actions;
  final Widget list;

  /// The add form, or the selected record. Null: the list alone.
  final Widget? side;

  static const double sideWidth = 400;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: title, description: description, actions: actions, compact: true),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final side = this.side;
            if (side == null) return list;
            if (c.maxWidth >= 660) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: list),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: c.maxWidth >= 820 ? sideWidth : 360,
                  // A visible thumb whenever the form runs past the bottom,
                  // so its Save buttons are never just out of sight.
                  child: ScrollWithThumb(child: side),
                ),
              ]);
            }
            return ListView(children: [
              side,
              const SizedBox(height: AppSpacing.lg),
              SizedBox(height: 440, child: list),
            ]);
          }),
        ),
      ],
    );
  }
}

/// A column that scrolls with its thumb always shown once it overflows, so
/// what sits below the fold (a form's Save, the queue's last steps) is
/// never just out of sight.
class ScrollWithThumb extends StatefulWidget {
  const ScrollWithThumb({super.key, required this.child});
  final Widget child;

  @override
  State<ScrollWithThumb> createState() => _ScrollWithThumbState();
}

class _ScrollWithThumbState extends State<ScrollWithThumb> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          child: widget.child,
        ),
      );
}

/// The step's records in a panel with a count, the add button and rows
/// that scroll inside it.
class RecordList extends StatelessWidget {
  const RecordList({
    super.key,
    required this.title,
    required this.rows,
    required this.empty,
    this.addLabel,
    this.onAdd,
    this.header,
  });

  final String title;
  final List<Widget> rows;
  final Widget empty;

  /// Null hides the button: the Cashier reads records they may not add.
  final String? addLabel;
  final VoidCallback? onAdd;

  /// A control under the heading, such as Vans / Operators.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
          child: Row(children: [
            Text(title, style: text.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            Text('${rows.length}', style: text.bodySmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            if (onAdd != null && addLabel != null)
              TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: Text(addLabel!)),
          ]),
        ),
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: header,
          ),
        const Divider(),
        Expanded(
          child: rows.isEmpty
              ? Center(child: SingleChildScrollView(child: empty))
              : Scrollbar(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => rows[i],
                  ),
                ),
        ),
      ]),
    );
  }
}

/// One record in a [RecordList]: a leading mark, the name, a line under it
/// and its badges. Selected, it takes the green tint and a bold name; the
/// side panel shows it.
class RecordRow extends StatelessWidget {
  const RecordRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badges = const [],
    this.selected = false,
    required this.onTap,
    required this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> badges;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? AppColors.primaryContainer : Colors.transparent,
        child: FocusRing(
          radius: 0,
          child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.surfaceSunken,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.md)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Two lines: what tells two long names apart is often at
                  // their end ("... Loading Bay 11").
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium!.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                ]),
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, alignment: WrapAlignment.end, children: badges),
              ],
            ]),
          ),
        ),
        ),
      ),
    );
  }
}

/// The side panel: a heading with an optional close, and its body.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.title, required this.child, this.onClose, this.closeLabel});

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: title,
      trailing: onClose == null
          ? null
          : IconButton(
              tooltip: closeLabel ?? 'Close',
              onPressed: onClose,
              icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
            ),
      child: child,
    );
  }
}

/// A van's plate as the pila board's magnet: a white tag with an ink edge
/// and the plate in bold, spaced figures.
class PlateTag extends StatelessWidget {
  const PlateTag(this.plate, {super.key});
  final String plate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.textPrimary, width: 1.5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        plate.toUpperCase(),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A form's buttons. Adding: "Save and add another" (the form clears for
/// the next record) beside "Save" (the record opens in the panel to
/// check). Editing: "Save changes" and "Cancel".
class FormButtons extends StatelessWidget {
  const FormButtons({
    super.key,
    required this.adding,
    required this.busy,
    required this.onSave,
    this.onCancel,
    this.saveLabel,
  });

  final bool adding;
  final bool busy;

  /// Null while the form cannot be saved. The flag is "add another".
  final void Function(bool another)? onSave;
  final VoidCallback? onCancel;

  /// Replaces "Save" / "Save changes".
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    final spinner = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
        if (adding) ...[
          FilledButton(
            onPressed: busy || save == null ? null : () => save(true),
            child: busy ? spinner : const Text('Save and add another'),
          ),
          OutlinedButton(
            onPressed: busy || save == null ? null : () => save(false),
            child: Text(saveLabel ?? 'Save'),
          ),
        ] else ...[
          FilledButton(
            onPressed: busy || save == null ? null : () => save(false),
            child: busy ? spinner : Text(saveLabel ?? 'Save changes'),
          ),
          if (onCancel != null) TextButton(onPressed: busy ? null : onCancel, child: const Text('Cancel')),
        ],
      ]),
    );
  }
}

/// Why the form cannot be saved yet, in a sentence, or the server's refusal.
class FormProblem extends StatelessWidget {
  const FormProblem(this.message, {super.key, this.refused = false});
  final String message;

  /// The server said no: danger, not a hint.
  final bool refused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: FactLine(refused ? Icons.error_outline : Icons.info_outline, message,
          colour: refused ? AppColors.danger : null),
    );
  }
}

/// A labelled fact in a record's panel: label left, value right.
class FactRow extends StatelessWidget {
  const FactRow(this.label, this.value, {super.key, this.colour});
  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 132, child: Text(label, style: text.bodySmall)),
        Expanded(
          child: Text(value, style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700, color: colour)),
        ),
      ]),
    );
  }
}

/// The pila board's numbered tile: an ink-edged square holding a number or
/// a mark. Filled green, the slot is done (or, on a route, where everyone
/// boards); muted, it waits on another step.
class QueueTile extends StatelessWidget {
  const QueueTile(this.label,
      {super.key, this.icon, this.filled = false, this.muted = false, this.done = false, this.size = 28});

  final String label;
  final IconData? icon;
  final bool filled;
  final bool muted;

  /// A check at the corner: done, and the number still says where it was
  /// in the queue.
  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = filled ? AppColors.onFill : (muted ? AppColors.textMuted : AppColors.textPrimary);
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.surfaceRaised,
        border: Border.all(
          color: filled ? AppColors.primary : (muted ? AppColors.disabled : AppColors.textPrimary),
          width: size >= 40 ? 2 : 1.5,
        ),
        borderRadius: BorderRadius.circular(size >= 40 ? 8 : 6),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: ink)
          : Text(label,
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.46,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
    );
    if (!done) return tile;
    final mark = size * 0.5;
    return Stack(clipBehavior: Clip.none, children: [
      tile,
      Positioned(
        right: -mark / 3,
        bottom: -mark / 3,
        child: Container(
          width: mark,
          height: mark,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Icon(Icons.check, size: mark * 0.7, color: AppColors.primary),
        ),
      ),
    ]);
  }
}

/// A step that waits on another: why, and the way there.
class BlockedNotice extends StatelessWidget {
  const BlockedNotice({super.key, required this.message, required this.action, required this.onAction});
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        QueueTile('', icon: Icons.lock_outline, muted: true),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(onPressed: onAction, child: Text(action)),
    ]);
  }
}
