import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// Asks for a physical headcount with −/+ buttons instead of a keyboard.
///
/// Two reasons. A keyboard is the wrong input for crew at a van door with
/// their hands full, and the Dispatcher counts with eyes on the cabin. And it starts at **zero**, never at the manifest's figure:
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
