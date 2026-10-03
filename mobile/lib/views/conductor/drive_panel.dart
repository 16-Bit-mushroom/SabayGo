import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../data/repositories/operations_repository.dart';
import '../safety/sos_button.dart';

/// What a driver needs from the phone once the van is moving -- and
/// nothing else.
///
/// Shown in place of the boarding stats when the person signed in is the
/// trip's driver and the trip has departed. Built to the in-vehicle
/// distraction guidelines rather than ordinary app conventions (NHTSA's
/// visual-manual guidelines; Android for Cars' driver-distraction rules):
///
/// * **One glance answers it.** The next stop is the largest thing on the
///   screen, and the two numbers under it are what changes at that stop:
///   who gets off, who is waiting to get on. No scrolling to find either.
/// * **Big, few targets.** Two controls -- "Arrived" and SOS -- each the
///   full width and at least 64dp high. A target that needs aiming needs a
///   longer look.
/// * **No typing.** Nothing here opens a keyboard; the headcount the
///   driver may be asked for is a stepper (see [showHeadcountDialog]).
/// * **No motion.** Nothing animates or auto-advances: a panel that changes
///   on its own draws the eye back to check what changed.
///
/// The van has no speed signal the app can read, so this cannot lock
/// itself while moving. It is a design that is safe to glance at, not an
/// enforcement -- the operating rule stays "act on it when stopped".
class DrivePanel extends StatelessWidget {
  const DrivePanel({
    super.key,
    required this.trip,
    required this.manifest,
    required this.currentStop,
    required this.onArrived,
  });

  final CrewTrip trip;
  final Manifest manifest;
  final int currentStop;
  final ValueChanged<int> onArrived;

  @override
  Widget build(BuildContext context) {
    final sequences = [for (final s in trip.stops) s.stopSequence]..sort();
    final last = sequences.isEmpty ? currentStop : sequences.last;
    final next = currentStop < last ? currentStop + 1 : null;

    final live = manifest.passengers.where((p) => !p.isCancelled && !p.isNoShow);
    // Aboard on leg k = boarded at or before stop k, getting off after it.
    // The same rule the seat allocator uses: boarding <= leg < alighting.
    final aboard = live
        .where((p) => p.isBoarded && p.boardingStop <= currentStop && currentStop < p.alightingStop)
        .length;
    final off = next == null ? 0 : live.where((p) => p.isBoarded && p.alightingStop == next).length;
    final on = next == null
        ? 0
        : live.where((p) => !p.isBoarded && !p.isUnpaid && p.boardingStop == next).length;

    return Container(
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            next == null ? 'FINAL STOP' : 'NEXT STOP',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            header: true,
            child: Text(
              trip.stopName(next ?? currentStop),
              style: const TextStyle(
                fontSize: 32,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            next == null
                ? 'Trip ends here. Remit cash from the manifest below once parked.'
                : 'Stop $next of $last · now leaving ${trip.stopName(currentStop)}',
            style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Three figures, one row, each labelled in words -- never a
          // colour-coded number the driver has to decode.
          Row(
            children: [
              _Figure(value: aboard, label: 'Aboard now'),
              _Figure(value: off, label: next == null ? 'Getting off' : 'Getting off next'),
              _Figure(value: on, label: 'To pick up next'),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (next != null) ...[
            FilledButton.icon(
              onPressed: () => onArrived(next),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.flag_outlined, size: 24),
              label: Text('Arrived at ${trip.stopName(next)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          // Full-width and on this panel, not only as an icon in the bar:
          // the moment it is needed is the moment there is least attention
          // to spare for finding it. It still takes two taps (category,
          // then send), so a full-width target cannot fire by accident.
          SizedBox(
            height: 64,
            child: SosButton(tripId: trip.tripId, compact: false),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 40,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}

/// Asks for a physical headcount with −/+ buttons instead of a keyboard.
///
/// Two reasons. A keyboard is the one input the in-vehicle guidelines rule
/// out outright, and the driver is the person most likely to be asked for
/// this count. And it starts at **zero**, never at the manifest's figure:
/// the count exists to be compared with the manifest and the camera, and
/// a pre-filled number invites confirming it rather than counting
/// (anchoring). An honest count that disagrees is the point.
///
/// Returns null if dismissed.
Future<int?> showHeadcountDialog(
  BuildContext context, {
  required String stopName,
  required int seatCapacity,
}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _HeadcountDialog(stopName: stopName, seatCapacity: seatCapacity),
    );

class _HeadcountDialog extends StatefulWidget {
  const _HeadcountDialog({required this.stopName, required this.seatCapacity});

  final String stopName;
  final int seatCapacity;

  @override
  State<_HeadcountDialog> createState() => _HeadcountDialogState();
}

class _HeadcountDialogState extends State<_HeadcountDialog> {
  int _count = 0;

  // Room above capacity on purpose: an overloaded van is exactly what the
  // count is meant to surface, so the control must be able to say so.
  int get _max => widget.seatCapacity + 10;

  @override
  Widget build(BuildContext context) {
    final over = _count > widget.seatCapacity;
    return AlertDialog(
      title: const Text('How many people are aboard?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Count everyone physically in the van at ${widget.stopName}, '
            'not counting yourself. The system compares this with the '
            'manifest and the camera.',
            style: const TextStyle(color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(
                icon: Icons.remove,
                label: 'One fewer',
                onPressed: _count > 0 ? () => setState(() => _count--) : null,
              ),
              // Takes what the two 64dp buttons leave. On a 320dp phone a
              // dialog's content is ~190dp wide, and a fixed-width number
              // overflowed it; the buttons keep their size, the digits
              // scale down instead.
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$_count people',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$_count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                label: 'One more',
                onPressed: _count < _max ? () => setState(() => _count++) : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            over
                ? 'More than the ${widget.seatCapacity} spaces in this van.'
                : '${widget.seatCapacity} spaces in this van',
            style: TextStyle(
              fontSize: 13,
              color: over ? AppColors.warning : AppColors.textMuted,
              fontWeight: over ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _count),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text('Record $_count aboard'),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: label,
        onPressed: onPressed,
        iconSize: 32,
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          side: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        icon: Icon(icon),
      );
}
