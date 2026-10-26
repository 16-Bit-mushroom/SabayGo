import 'package:flutter/material.dart';

import '../tokens.dart';

/// The keyboard's place on a custom tappable -- a menu entry, a queue
/// step, a record row -- drawn as a 2px ring when focus arrives by
/// keyboard. Buttons get the same ring from the theme; an [InkWell] on its
/// own shows only a faint fill, which fails WCAG 2.4.7 on a tinted row.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.color,
    this.radius = AppRadius.md,
  });

  final Widget child;

  /// Terminal green by default; white on the green rail.
  final Color? color;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // A pointer click never focuses an InkWell, so a ring only ever means
    // the keyboard; the highlight mode check covers touch screens.
    final show = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // The ring is always there, transparent at rest: a widget that only
    // appears on focus would change the tree under it, rebuild the control
    // that holds focus, and drop the focus it is meant to show.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: show ? widget.color ?? AppColors.primary : Colors.transparent,
            width: AppSizing.focusOutline,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
  }
}
