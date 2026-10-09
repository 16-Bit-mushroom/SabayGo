import 'package:flutter/material.dart';

import '../tokens.dart';

/// What a status means, independent of the word for it.
enum Tone { success, warning, danger, info, neutral }

/// A status as a tinted pill with a dot and a word -- never colour alone
/// (WCAG 1.4.1).
///
/// The trip and passenger words live here, once. They are the conductor
/// app's words in sentence case, so a dispatcher on the phone with a
/// conductor is using the words on the conductor's screen; three screens
/// used to keep their own copies of this mapping.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral});

  /// A trip's status (`trips.status`).
  factory StatusBadge.trip(String status, {Key? key}) {
    final (label, tone) = switch (status) {
      'scheduled' => ('Scheduled', Tone.info),
      'boarding' => ('Boarding', Tone.success),
      'departed' => ('Departed', Tone.warning),
      'completed' => ('Completed', Tone.neutral),
      'cancelled' => ('Cancelled', Tone.danger),
      _ => (status, Tone.neutral),
    };
    return StatusBadge(label, tone: tone, key: key);
  }

  /// A passenger's status on a trip's passenger list.
  factory StatusBadge.passenger(String status, {Key? key}) {
    final (label, tone) = switch (status) {
      'boarded' => ('Boarded', Tone.success),
      'checked_in' => ('At terminal', Tone.info),
      'confirmed' => ('Not yet boarded', Tone.warning),
      'pending' => ('Unpaid', Tone.neutral),
      'no_show' => ('No-show', Tone.danger),
      'completed' => ('Completed', Tone.neutral),
      _ => (status, Tone.neutral),
    };
    return StatusBadge(label, tone: tone, key: key);
  }

  final String label;
  final Tone tone;

  static (Color, Color) colours(Tone tone) => switch (tone) {
        Tone.success => (AppColors.success, AppColors.successContainer),
        Tone.warning => (AppColors.warning, AppColors.warningContainer),
        Tone.danger => (AppColors.danger, AppColors.dangerContainer),
        Tone.info => (AppColors.info, AppColors.infoContainer),
        Tone.neutral => (AppColors.textMuted, AppColors.surfaceSunken),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colours(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
