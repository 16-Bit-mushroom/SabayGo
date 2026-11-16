import 'package:flutter/material.dart';

import '../tokens.dart';
import 'focus_ring.dart';

/// The one input box (11 Nov): every dropdown, picker and read-only value
/// in a row of fields is [AppSizing.field] high with the same edge, so the
/// row lines up and each box is the same target.
///
/// Its states, the same everywhere:
///   rest      white, the [AppColors.border] edge
///   hover     the edge turns [AppColors.primaryLight], the see-through wash
///   problem   a 2 px red edge on the red tint, with the reason under it
///             in words (never colour alone) -- the Post that would fail is
///             disabled beside it (poka-yoke: the mistake cannot be sent)
///   fixed     a value that cannot change here: sunken, a lock, no hover
class FieldBox extends StatefulWidget {
  const FieldBox({
    super.key,
    required this.child,
    this.icon,
    this.onTap,
    this.chevron = false,
    this.fixed = false,
    this.problem = false,
    this.semanticLabel,
  });

  final Widget child;
  final IconData? icon;

  /// A picker: the whole box opens it.
  final VoidCallback? onTap;

  /// The down-chevron a picker shows; a [FieldSelect] draws its own.
  final bool chevron;
  final bool fixed;
  final bool problem;
  final String? semanticLabel;

  @override
  State<FieldBox> createState() => _FieldBoxState();
}

class _FieldBoxState extends State<FieldBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hot = _hover && !widget.fixed;
    final edge = widget.problem
        ? AppColors.danger
        : (hot ? AppColors.primaryLight : (widget.fixed ? AppColors.divider : AppColors.border));
    final fill = widget.problem
        ? AppColors.dangerContainer
        : (widget.fixed ? AppColors.surfaceSunken : AppColors.surfaceRaised);
    final iconColor = widget.problem ? AppColors.danger : (hot ? AppColors.primary : AppColors.textMuted);
    final box = AnimatedContainer(
      duration: still ? Duration.zero : AppDuration.quick,
      height: AppSizing.field,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: edge, width: widget.problem ? 2 : 1),
      ),
      foregroundDecoration: BoxDecoration(
        color: hot && !widget.problem ? AppColors.hoverWash : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(children: [
        if (widget.icon != null || widget.fixed) ...[
          Icon(widget.fixed ? Icons.lock_outline : widget.icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.problem ? AppColors.danger : AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            child: widget.child,
          ),
        ),
        if (widget.chevron) Icon(Icons.expand_more, size: 20, color: iconColor),
      ]),
    );
    final hoverable = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: box,
    );
    if (widget.onTap == null) return hoverable;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusRing(
        radius: AppRadius.sm,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            hoverColor: Colors.transparent,
            onTap: widget.onTap,
            child: hoverable,
          ),
        ),
      ),
    );
  }
}

/// A dropdown in a [FieldBox]: the same box, the same chevron.
class FieldSelect<T> extends StatelessWidget {
  const FieldSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FieldBox(
        icon: icon,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.any((i) => i.$1 == value) ? value : null,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, size: 20),
            iconEnabledColor: AppColors.textMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            dropdownColor: AppColors.surfaceRaised,
            focusColor: Colors.transparent,
            style: const TextStyle(
                fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            items: [
              for (final (v, label) in items)
                DropdownMenuItem<T>(value: v, child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged,
          ),
        ),
      );
}

/// The label over a field: small capitals, one height for every field in
/// the row (so the boxes under them start on one line), with an optional
/// quick link at its right ("+ Next slot").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.icon, this.link, this.onLink});

  final String text;
  final IconData? icon;
  final String? link;
  final VoidCallback? onLink;

  static const double height = 20;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6, fontSize: 11, height: 1);
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: AppColors.primary), const SizedBox(width: 4)],
        Expanded(child: Text(text.toUpperCase(), style: style, overflow: TextOverflow.ellipsis)),
        if (link != null)
          _Link(link!, onLink),
      ]),
    );
  }
}

class _Link extends StatefulWidget {
  const _Link(this.text, this.onTap);
  final String text;
  final VoidCallback? onTap;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _hover ? AppColors.hoverWash : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(widget.text,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      decoration: _hover ? TextDecoration.underline : null,
                      decorationColor: AppColors.primary)),
            ),
          ),
        ),
      );
}
