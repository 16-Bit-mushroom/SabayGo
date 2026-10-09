import 'package:flutter/material.dart';

import '../../core/design/components/status_badge.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/audit_repository.dart';

/// What an audit result means, in words -- the backend's reading
/// (domain/audit_reading.py), not a re-derivation here.
///
/// Shared by the Passenger Count Checks screen and the Trips screen so the office
/// reads the same sentence about the same result in both places. The
/// colour follows the meaning, not the sign: more people than the manifest
/// is the leakage case (danger), fewer is a camera-view question (warning),
/// a match is fine (success).
class AuditReadingCard extends StatelessWidget {
  const AuditReadingCard({super.key, required this.audit});

  final PendingAudit audit;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (audit.verdict) {
      'more_than_manifest' => (AppColors.danger, AppColors.dangerContainer, Icons.report_outlined),
      'fewer_than_manifest' => (AppColors.warning, AppColors.warningContainer, Icons.visibility_off_outlined),
      _ => (AppColors.success, AppColors.successContainer, Icons.check_circle_outline),
    };
    final text = Theme.of(context).textTheme;
    final body = text.bodySmall!.copyWith(color: AppColors.textPrimary, height: 1.45);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(left: BorderSide(color: fg, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(audit.headline,
                    style: text.bodyMedium!.copyWith(color: fg, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Two short lines under the headline -- what it means, what to do.
          // Never a paragraph: this sits beside a manifest.
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(audit.explanation, style: body),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Next: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: audit.nextStep),
                  ]),
                  style: body,
                ),
              ],
            ),
          ),
          if (audit.caution != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(audit.caution!,
                      style: body.copyWith(color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// An audit's review state in the office's words -- one mapping for every
/// screen, so a check is never "Matched" on one page and "no action
/// needed" on another.
StatusBadge auditOutcomeBadge(String status) {
  final (label, tone) = switch (status) {
    'pending' => ('Needs review', Tone.warning),
    'resolved' => ('Problem confirmed', Tone.danger),
    'ignored' => ('Dismissed', Tone.neutral),
    'reconciled' => ('Matched', Tone.success),
    'failed' => ('Camera failed', Tone.warning),
    _ => (status, Tone.neutral),
  };
  return StatusBadge(label, tone: tone);
}
