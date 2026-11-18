import 'package:flutter/material.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';

/// One Setup step (11 Nov redesign): its heading with the one primary
/// action, **Add**, and the step's records as a table across the page.
///
/// The side panel is shown only when it has something to do -- the record
/// clicked ([detail]) or the add form after Add ([addForm]) -- and closes
/// with its ✕, giving the table its width back (progressive disclosure:
/// a form left open beside every list was the page's clutter). A step
/// with no records yet opens the form at once ([openWhenEmpty]): there is
/// nothing else to do there.
///
/// Wide enough, the table and the panel sit side by side; narrower, the
/// panel comes first and the table follows at a fixed height.
class StepFrame extends StatefulWidget {
  const StepFrame({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    required this.list,
    this.detail,
    this.addForm,
    this.addLabel,
    this.onAdd,
    this.openWhenEmpty = false,
    this.addOnOpen = false,
  });

  final String title;
  final String description;
  final List<Widget> actions;
  final Widget list;

  /// The record open in the panel (or a notice about the step); it wins
  /// over the add form.
  final Widget? detail;

  /// The add form's panel; null when this person may not add.
  final Widget? addForm;

  /// The header button that opens [addForm] ("Add terminal").
  final String? addLabel;

  /// Called when Add is pressed, so the step can drop its selection.
  final VoidCallback? onAdd;

  /// No records yet: the add form is open and has no ✕.
  final bool openWhenEmpty;

  /// Open with the add form showing, once (12 Nov): another page sent the
  /// person here to make one -- the Timetable's "Add a new route".
  final bool addOnOpen;

  static const double sideWidth = 420;

  @override
  State<StepFrame> createState() => _StepFrameState();
}

class _StepFrameState extends State<StepFrame> {
  late bool _adding = widget.addOnOpen;

  @override
  void didUpdateWidget(StepFrame old) {
    super.didUpdateWidget(old);
    // A record opened while adding: the record wins, and closing it
    // returns to the table rather than to a form nobody asked for again.
    if (widget.detail != null) _adding = false;
  }

  void _openAdd() {
    widget.onAdd?.call();
    setState(() => _adding = true);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final showingAdd = w.detail == null && w.addForm != null && (_adding || w.openWhenEmpty);
    final side = w.detail ?? (showingAdd ? w.addForm : null);
    final scoped = side == null
        ? null
        : _StepFrameScope(
            // The add form closes with the panel's ✕ unless it is the only
            // thing the step can show.
            closeAdd: showingAdd && !w.openWhenEmpty ? () => setState(() => _adding = false) : null,
            child: side,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: w.title,
          description: w.description,
          compact: true,
          actions: [
            ...w.actions,
            if (w.addForm != null && w.addLabel != null && !showingAdd)
              FilledButton.icon(onPressed: _openAdd, icon: const Icon(Icons.add, size: 18), label: Text(w.addLabel!)),
          ],
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (scoped == null) return w.list;
            if (c.maxWidth >= 900) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: w.list),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: c.maxWidth >= 1100 ? StepFrame.sideWidth : 360,
                  // A visible thumb whenever the form runs past the bottom,
                  // so its Save buttons are never just out of sight.
                  child: ScrollWithThumb(child: scoped),
                ),
              ]);
            }
            return ListView(children: [
              scoped,
              const SizedBox(height: AppSpacing.lg),
              SizedBox(height: 440, child: w.list),
            ]);
          }),
        ),
      ],
    );
  }
}

/// Lets the add form's [SidePanel] close itself through its ✕.
class _StepFrameScope extends InheritedWidget {
  const _StepFrameScope({required this.closeAdd, required super.child});
  final VoidCallback? closeAdd;

  static VoidCallback? closeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StepFrameScope>()?.closeAdd;

  @override
  bool updateShouldNotify(_StepFrameScope old) => old.closeAdd != closeAdd;
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

/// A table column in a [RecordList]: its head, its share of the width,
/// and whether its figures sit at the right.
class RecordColumn {
  const RecordColumn(this.label, {this.flex = 2, this.end = false});
  final String label;
  final int flex;
  final bool end;
}

/// The step's records as a table (11 Nov): a title with the count, column
/// heads in the sheets' style when [columns] are given, and rows that
/// scroll inside it. The step's Add is in its header, not here.
class RecordList extends StatelessWidget {
  const RecordList({
    super.key,
    required this.title,
    required this.rows,
    required this.empty,
    this.header,
    this.columns,
    this.leadingWidth = 0,
  });

  final String title;
  final List<Widget> rows;
  final Widget empty;

  /// A control under the heading, such as Vans / Operators.
  final Widget? header;

  /// The table's columns; the rows' [RecordRow.cells] follow them.
  final List<RecordColumn>? columns;

  /// The width the rows' leading marks take, so the heads line up.
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final head = text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.2);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                Text(title, style: text.titleMedium),
                const SizedBox(width: AppSpacing.sm),
                Text('${rows.length}', style: text.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              ?header,
            ],
          ),
        ),
        if (columns != null && rows.isNotEmpty)
          Container(
            height: 40,
            padding: EdgeInsets.only(left: AppSpacing.xl + leadingWidth, right: AppSpacing.md + RecordRow.chevronWidth),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider), bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(children: [
              for (final col in columns!)
                Expanded(
                  flex: col.flex,
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Text(col.label, style: head, textAlign: col.end ? TextAlign.right : TextAlign.left),
                  ),
                ),
            ]),
          )
        else
          const Divider(),
        Expanded(
          child: rows.isEmpty
              ? Center(child: SingleChildScrollView(child: empty))
              : Scrollbar(
                  child: ListView.builder(itemCount: rows.length, itemBuilder: (_, i) => rows[i]),
                ),
        ),
      ]),
    );
  }
}

/// One record in a [RecordList]. With [cells] and [columns] it is a table
/// row; without, a name with a line under it and its badges. Selected, it
/// takes the green tint and the panel shows it.
class RecordRow extends StatefulWidget {
  const RecordRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingWidth = 0,
    this.badges = const [],
    this.cells,
    this.columns,
    this.selected = false,
    required this.onTap,
    required this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// The leading mark's width, the same for every row of a table.
  final double leadingWidth;
  final List<Widget> badges;
  final List<Widget>? cells;
  final List<RecordColumn>? columns;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  /// The chevron's column at the end of every row, kept in the heads too
  /// so the columns line up.
  static const double chevronWidth = 28;

  @override
  State<RecordRow> createState() => _RecordRowState();
}

/// Under the pointer (11 Nov, "the hover is too bland"): the see-through
/// emerald wash over the whole row, a 3 px emerald bar sliding in at its
/// left edge, the chevron showing that the row opens, and the cursor a
/// hand -- the whole row is the target, not its name (Fitts). Selected,
/// the bar stays and the tint is the soft emerald.
class _RecordRowState extends State<RecordRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final text = Theme.of(context).textTheme;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final speed = still ? Duration.zero : AppDuration.quick;
    final lit = _hover || w.selected;
    final cols = w.columns;
    final Widget body;
    if (w.cells != null && cols != null) {
      body = Row(children: [
        if (w.leading != null) SizedBox(width: w.leadingWidth, child: Align(alignment: Alignment.centerLeft, child: w.leading)),
        for (var i = 0; i < w.cells!.length && i < cols.length; i++)
          Expanded(
            flex: cols[i].flex,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Align(alignment: cols[i].end ? Alignment.centerRight : Alignment.centerLeft, child: w.cells![i]),
            ),
          ),
      ]);
    } else {
      body = Row(children: [
        if (w.leading != null) ...[w.leading!, const SizedBox(width: AppSpacing.md)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Two lines: what tells two long names apart is often at
            // their end ("... Loading Bay 11").
            AnimatedDefaultTextStyle(
              duration: speed,
              style: text.bodyMedium!.copyWith(
                  fontWeight: w.selected ? FontWeight.w700 : FontWeight.w500,
                  color: _hover ? AppColors.primary : AppColors.textPrimary),
              child: Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (w.subtitle != null) Text(w.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ]),
        ),
        if (w.badges.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, alignment: WrapAlignment.end, children: w.badges),
        ],
      ]);
    }
    return Semantics(
      button: true,
      selected: w.selected,
      label: w.semanticLabel,
      excludeSemantics: true,
      onTap: w.onTap,
      child: Material(
        color: w.selected ? AppColors.primaryContainer : Colors.transparent,
        child: FocusRing(
          radius: 0,
          child: InkWell(
            onTap: w.onTap,
            onHover: (h) => setState(() => _hover = h),
            hoverColor: w.selected ? AppColors.pressWash : AppColors.hoverWash,
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceSunken))),
              child: Stack(children: [
                // The accent bar slides in from the left edge.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: speed,
                    curve: Curves.easeOut,
                    width: lit ? 3 : 0,
                    color: AppColors.accent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                  child: Row(children: [
                    Expanded(child: body),
                    SizedBox(
                      width: RecordRow.chevronWidth,
                      child: AnimatedOpacity(
                        duration: speed,
                        opacity: lit ? 1 : 0,
                        child: AnimatedSlide(
                          duration: speed,
                          offset: Offset(_hover && !still ? 0.15 : 0, 0),
                          child: const Icon(Icons.chevron_right, size: 20, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain table cell: one line, the strong one for a record's name.
class CellText extends StatelessWidget {
  const CellText(this.text, {super.key, this.strong = false, this.muted = false});
  final String text;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodyMedium;
    return Text(text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: t?.copyWith(
            fontWeight: strong ? FontWeight.w600 : null,
            color: muted ? AppColors.textMuted : null,
            fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

/// The side panel: a heading with a ✕, and its body. A record's panel
/// closes through [onClose]; the add form through its [StepFrame].
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.title, required this.child, this.onClose, this.closeLabel, this.info});

  final String title;

  /// What the form is for, behind an (i) beside its title.
  final String? info;
  final Widget child;
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? _StepFrameScope.closeOf(context);
    return Panel(
      title: title,
      info: info,
      trailing: close == null
          ? null
          : IconButton(
              tooltip: closeLabel ?? 'Close',
              onPressed: close,
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
      // A plate is one line, always: in a narrow column it shrinks a little
      // rather than breaking "ABC-1234" into "ABC-123" over "4".
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          plate.toUpperCase(),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
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
