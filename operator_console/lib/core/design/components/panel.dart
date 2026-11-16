import 'package:flutter/material.dart';

import '../tokens.dart';
import 'page_header.dart';
import 'focus_ring.dart';

/// A rounded card, optionally with a heading row: icon, title, and one
/// control at the right (the reference dashboard's tile).
///
/// Replaces a private `_Panel` / `Card(...)` written separately in most
/// screens, each with its own radius and border.
///
/// [fill] makes the body take the remaining height -- for a panel placed
/// in an `Expanded` whose body is a list. Leave it off inside a scroll
/// view, where there is no remaining height to take.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.fill = false,
    this.color,
    this.info,
  });

  final Widget child;
  final String? title;

  /// What the box is for, behind an (i) beside the title (12 Nov).
  final String? info;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool fill;

  /// Defaults to [AppColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heading = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Row(children: [
                    Flexible(child: Text(title!, style: text.titleSmall)),
                    if (info != null) ...[const SizedBox(width: AppSpacing.xs), InfoTip(info!, size: 16)],
                  ]),
                ),
                ?trailing,
              ],
            ),
          );
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceRaised,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: heading == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: [heading, fill ? Expanded(child: child) : child],
            ),
    );
  }
}

/// One figure on a card, as in the owner's VerdantPulse reference (10
/// Nov): what it counts at the top left, its icon on a soft tile at the
/// top right, the number, an optional line under it, and an optional
/// progress bar for a real ratio (paid of owed, booked of capacity) with
/// its percentage. Never a ratio the system does not have: no growth
/// percentages, no scores.
///
/// A figure with a status keeps it in its number and its tile -- green for
/// paid, ochre for due, red for danger -- and the label still says it in
/// words.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.caption,
    this.progress,
    this.progressLabel,
    this.onTap,
    this.opens,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Opens the page this figure comes from; the card then shows it can be
  /// clicked (pointer, a green edge on hover, a chevron).
  final VoidCallback? onTap;

  /// Where a click goes, for a screen reader and the tooltip: "Money".
  final String? opens;

  /// Colour of the small icon beside the label: the status colour that
  /// matches the label's meaning. The figure itself stays the type colour
  /// (10 Nov, toned down): the label says the meaning in words.
  final Color? color;
  final String? caption;

  /// A real ratio, 0 to 1, drawn as a bar with its percentage. Null: no bar.
  final double? progress;

  /// What the bar measures ("Paid of ₱343.00 owed"). One bar a page at
  /// most: a bar on every card is decoration, not information.
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = progress?.clamp(0.0, 1.0);
    // Toned down (10 Nov): white, a small icon beside the label instead of
    // a tinted tile, the figure in the type colour, one flat bar.
    final card = Container(
      // Room for one caption line, so cards in a row line up with or without one.
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs + 2, top: 1),
                  child: ExcludeSemantics(child: Icon(icon, size: 16, color: color ?? AppColors.textMuted)),
                ),
              // Wraps rather than ellipsising: a cut label ("Not yet boar…")
              // hides what the figure counts.
              Expanded(
                child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: text.bodySmall),
          ],
          if (p != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: Text(progressLabel ?? '',
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              ),
              Text('${(p * 100).round()} %',
                  style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: AppSpacing.xs + 2),
            Semantics(
              label: '${progressLabel ?? label}: ${(p * 100).round()} percent',
              child: ExcludeSemantics(child: _Bar(p)),
            ),
          ],
        ],
      ),
    );
    return onTap == null
        ? card
        : ClickableCard(onTap: onTap!, label: '$label, $value. Opens ${opens ?? label}.', child: card);
  }
}

/// A card that opens a page: the pointer turns to a hand, the edge turns
/// the secondary-hover green under it, the keyboard reaches it with the
/// focus ring, and a screen reader hears where it goes.
class ClickableCard extends StatefulWidget {
  const ClickableCard({super.key, required this.child, required this.onTap, required this.label});
  final Widget child;
  final VoidCallback onTap;
  final String label;

  @override
  State<ClickableCard> createState() => _ClickableCardState();
}

class _ClickableCardState extends State<ClickableCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppRadius.lg));
    // Under the pointer the card rises 2 px on the soft green lift and
    // takes the secondary-hover edge: it says "this opens" before the
    // click. Reduced motion keeps the edge and drops the movement.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: FocusRing(
        radius: AppRadius.lg,
        child: AnimatedContainer(
          duration: still ? Duration.zero : AppDuration.quick,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover && !still ? -2 : 0, 0),
          decoration: BoxDecoration(borderRadius: radius, boxShadow: _hover ? AppShadow.lift : AppShadow.none),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              onHover: (h) => setState(() => _hover = h),
              hoverColor: Colors.transparent,
              child: AnimatedContainer(
                duration: still ? Duration.zero : AppDuration.quick,
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: _hover ? AppColors.primaryLight : Colors.transparent, width: 1.5),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 6 px flat bar: green text colour on the soft tint track.
class _Bar extends StatelessWidget {
  const _Bar(this.value);
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: AppColors.primaryContainer)),
            FractionallySizedBox(
              widthFactor: value,
              heightFactor: 1,
              child: const ColoredBox(color: AppColors.primary),
            ),
          ]),
        ),
      );
}

/// Cards in one row across the page, equal widths, one height, so their
/// outer edges are the statements' edges below. On a narrow window they
/// wrap at a fixed width instead.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = AppSpacing.md;
        if (c.maxWidth < children.length * 180 + (children.length - 1) * gap) {
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final w in children) SizedBox(width: 216, child: w),
          ]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: w),
            ],
          ]),
        );
      });
}
