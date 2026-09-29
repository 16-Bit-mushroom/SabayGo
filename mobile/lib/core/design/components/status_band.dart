import 'package:flutter/material.dart';

import '../tokens.dart';
import 'status_chip.dart';

/// What is happening, and what to do about it.
///
/// A chip labels a thing in a list. A band answers the question a whole
/// screen exists to answer, and the boarding pass needed one badly: it was
/// telling the passenger their status in four places at once — a coloured
/// card header, a pill above the QR, a sentence under it, and a bordered
/// payment box — each with its own colour logic, and none of them saying
/// what to do next.
///
/// [body] is that sentence. A state without a next step ("AWAITING TERMINAL
/// ARRIVAL") leaves the person holding the phone to work out whether it is
/// their turn to act.
///
/// Set [liveRegion] where the state can change while the screen is open,
/// as it does when a payment webhook lands mid-poll. A screen reader then
/// announces the change instead of leaving a blind passenger tapping
/// "check again" on a ticket that has already been confirmed.
class StatusBand extends StatelessWidget {
  const StatusBand({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.liveRegion = false,
    super.key,
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final String body;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Semantics(
      liveRegion: liveRegion,
      container: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          // The tints are deliberately pale, which leaves them close to the
          // scaffold. A border in the tone's own colour gives the band an
          // edge without darkening the fill the text has to sit on.
          border: Border.all(color: tone.fg.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: tone.fg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium!.copyWith(color: tone.fg),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body,
                    // Body text stays in the ink colour rather than the
                    // tone's: a paragraph set in the status colour is
                    // harder to read and spends emphasis on the part that
                    // needs none.
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
