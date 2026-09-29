import 'package:flutter/material.dart';

import '../tokens.dart';

/// What a status means, rather than what colour it is.
///
/// Call sites pass a tone, not a `Color`. That is the point: before this,
/// three screens each kept their own `(label, colour)` switch, and the
/// colours had drifted into `Colors.blue`, `Colors.teal` and
/// `Colors.deepOrange` — 3.12:1, 3.67:1 and 3.16:1 against white, all
/// below AA, all of them labelling manifest rows a conductor reads in
/// daylight.
enum StatusTone {
  /// Done, paid, aboard.
  success,

  /// Informational, neither good nor bad: at the terminal, queued to sync.
  info,

  /// Needs someone's attention but nothing has gone wrong yet.
  warning,

  /// Failed, cancelled, flagged.
  danger,

  /// Brand-coloured, for a neutral default state such as "SCHEDULED".
  brand,

  /// Past or inactive. Deliberately grey, so a finished trip recedes.
  muted;

  /// Public, because a chip is not the only thing a tone colours: the
  /// boarding pass states its status in a full-width band, and that band
  /// needs this exact pair. Exposing the pair on the tone keeps the one
  /// guarantee that matters — a caller can choose a *meaning*, and never a
  /// foreground without the background it was verified against.
  Color get fg => switch (this) {
        StatusTone.success => AppColors.success,
        StatusTone.info => AppColors.info,
        StatusTone.warning => AppColors.warning,
        StatusTone.danger => AppColors.danger,
        StatusTone.brand => AppColors.primary,
        StatusTone.muted => AppColors.textMuted,
      };

  Color get bg => switch (this) {
        StatusTone.success => AppColors.successContainer,
        StatusTone.info => AppColors.infoContainer,
        StatusTone.warning => AppColors.warningContainer,
        StatusTone.danger => AppColors.dangerContainer,
        StatusTone.brand => AppColors.primaryContainer,
        StatusTone.muted => AppColors.surface,
      };
}

/// A small, legible state label.
///
/// Every tone/tint pair is verified at 4.7:1 or better, so the chip cannot
/// be constructed in a combination that fails AA — the contrast decision is
/// made here once instead of at each call site.
///
/// **Wrap it in `Flexible` when it sits in a `Row`.** A `Row` hands an
/// inflexible child unbounded width, so the chip sizes to its whole label and
/// shoves its neighbours off the edge; the `Flexible` text inside only
/// ellipsises once something bounds the chip. "AWAITING PAYMENT" at 200% text
/// on a 320dp phone is the case that finds this.
///
/// The [label] is never decorative. WCAG 1.4.1 forbids carrying meaning by
/// colour alone, so the word is the status and the colour only reinforces
/// it; [icon] reinforces it again for anyone who cannot distinguish the
/// tints. Screen readers get "status: BOARDED" rather than a bare word
/// floating in the row.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = tone.fg;
    return Semantics(
      label: 'status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: AppSpacing.xs + 1),
            ],
            // Not `Text(label.toUpperCase())`: callers already pass the
            // casing they want, and forcing capitals here would shout a
            // sentence-case label.
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
