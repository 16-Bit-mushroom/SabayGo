import 'package:flutter/material.dart';

import '../../../core/design/components/journey_strip.dart';
import '../../../core/design/components/money.dart';
import '../../../core/design/components/sheet.dart';
import '../../../core/design/components/status_band.dart';
import '../../../core/design/components/status_chip.dart';
import '../../../core/design/tokens.dart';
import '../../../core/util/when.dart';
import '../../../models/uv_trip_model.dart';
import 'camera_notice.dart';

/// The last screen before a seat is held, so it answers the questions that
/// decide it: when, where, how much, and how many are left.
///
/// The fare is the largest thing on the sheet because it is what the
/// decision turns on (20 Nov redesign, after Gemini's study): time and fare
/// on one line, the journey on its own tint, the van and the seats side by
/// side, then the cash rule and the camera notice before the button.
class TripDetailsSheet extends StatelessWidget {
  const TripDetailsSheet({
    super.key,
    required this.trip,
    required this.onBook,
    this.onBookForOther,
  });

  final UvTripModel trip;
  final VoidCallback onBook;

  /// Book for someone else (brief 2.6); null where it is not offered.
  final VoidCallback? onBookForOther;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final eta = trip.estimatedArrivalTime;
    final scarce = !trip.isFull && (trip.isNearlyFull || trip.occupancyRatio >= 0.8);
    final roomy = MediaQuery.textScalerOf(context).scale(1) <= 1.3;

    final seatsChip = trip.isFull
        ? const StatusChip('FULL', tone: StatusTone.danger)
        : StatusChip(
            '${trip.availableSeats} OF ${trip.totalSeats}${scarce ? ' · FILLING UP' : ''}',
            tone: scarce ? StatusTone.warning : StatusTone.success,
          );
    final facts = [
      _Fact(label: 'Van', child: Text(trip.plateNumber ?? trip.operatorName ?? 'Assigned later',
          style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w700))),
      _Fact(label: 'Seats left', child: seatsChip),
    ];

    return AppSheet(
      title: '${clockTime(trip.departureTime)} departure',
      subtitle: dayFriendly(trip.departureTime),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The fare, at the size of the decision it drives. Exact, from
            // the LTFRB pairwise terminal matrix for this pair of stops --
            // not distance-based and not dynamic, so it is not hedged.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fare for this journey', style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
                      Text('Set by LTFRB for these two terminals', style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Money(
                  trip.approximateFare,
                  style: text.headlineMedium!.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.divider),
              ),
              child: JourneyStrip(
                origin: trip.origin.name,
                destination: trip.destination.name,
                originNote: 'Departs ${clockTime(trip.departureTime)}',
                // No invented arrival. The search response carries none: it
                // depends on where the passenger gets off, and a made-up time
                // on the screen where they commit is the worst place for one.
                destinationNote: eta == null ? null : 'Arrives about ${clockTime(eta)}',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Van and seats side by side; one above the other at large text.
            roomy
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: facts[0]),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: facts[1]),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    facts[0],
                    const SizedBox(height: AppSpacing.sm),
                    facts[1],
                  ]),
            if (!trip.isFull) ...[
              const SizedBox(height: AppSpacing.lg),
              // Cash only (rev 721): there is no next payment screen, and the
              // exact pay-before time is the server's, shown once reserved.
              const StatusBand(
                tone: StatusTone.warning,
                icon: Icons.payments_outlined,
                title: 'Cash at the terminal',
                body: 'You pay the Dispatcher in cash at the terminal. A seat still unpaid by its '
                    'pay-before time goes to someone else; you see the time once you reserve.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const CameraNotice(),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              // Reserve first, pay the Dispatcher in cash at the terminal: the
              // seat has to be held before there is anything to pay for.
              onPressed: trip.isFull ? null : onBook,
              child: Text(trip.isFull ? 'This trip is full' : 'Reserve a seat'),
            ),
            if (!trip.isFull && onBookForOther != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onBookForOther,
                icon: const Icon(Icons.accessible_forward),
                label: const Text('Book for someone else (home pickup)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small card: a label over its answer.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            child,
          ],
        ),
      );
}
