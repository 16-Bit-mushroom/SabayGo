import 'package:flutter/material.dart';

import '../../../core/design/components/info_row.dart';
import '../../../core/design/components/journey_strip.dart';
import '../../../core/design/components/money.dart';
import '../../../core/design/components/sheet.dart';
import '../../../core/design/components/status_band.dart';
import '../../../core/design/components/status_chip.dart';
import '../../../core/design/tokens.dart';
import '../../../core/util/when.dart';
import '../../../models/uv_trip_model.dart';

/// The last screen before a space is held, so it answers the questions that
/// decide it: when, where, how much, and how many are left.
///
/// It used to answer them in three bordered boxes — a blue-tinted timeline, a
/// grey vehicle box, and a loose row about spaces — each box a container with
/// its own fill, border and radius. Three nested frames to hold six facts.
/// The facts are the same; the frames are gone, and the fare is now the
/// largest thing on the sheet because it is what the decision turns on.
class TripDetailsSheet extends StatelessWidget {
  const TripDetailsSheet({
    super.key,
    required this.trip,
    required this.onBook,
  });

  final UvTripModel trip;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final eta = trip.estimatedArrivalTime;
    final scarce = !trip.isFull &&
        (trip.isNearlyFull || trip.occupancyRatio >= 0.8);

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
            JourneyStrip(
              origin: trip.origin.name,
              destination: trip.destination.name,
              originNote: 'Departs ${clockTime(trip.departureTime)}',
              // No invented arrival. The search response carries none: it
              // depends on where the passenger gets off, and a made-up time
              // on the screen where they commit is the worst place for one.
              destinationNote:
                  eta == null ? null : 'Arrives about ${clockTime(eta)}',
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),

            // The fare, at the size of the decision it drives. Exact, from
            // the LTFRB pairwise terminal matrix for this pair of stops —
            // not distance-based and not dynamic, so it is not hedged.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fare for this journey', style: text.bodyMedium),
                      Text(
                        'Set by LTFRB for these two terminals',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Money(
                  trip.approximateFare,
                  style: text.headlineMedium!
                      .copyWith(color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),

            AppInfoRow(
              label: 'Van',
              value: trip.plateNumber ?? trip.operatorName ?? 'Assigned later',
            ),
            const SizedBox(height: AppSpacing.md),
            AppInfoRow(
              label: 'Route',
              value: trip.tripLabel.isEmpty ? '—' : trip.tripLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            AppInfoRow(
              label: 'Space left',
              // Not a seat count. UV Express assigns no seat numbers —
              // capacity is counted per section of road, and a passenger is
              // never given a position in the van.
              value: trip.isFull
                  ? 'None'
                  : '${trip.availableSeats} of ${trip.totalSeats}',
              valueWidget: trip.isFull
                  ? const StatusChip('FULL', tone: StatusTone.danger)
                  : null,
            ),

            if (scarce) ...[
              const SizedBox(height: AppSpacing.lg),
              StatusBand(
                tone: StatusTone.warning,
                icon: Icons.priority_high,
                title: 'Filling up',
                body: '${trip.availableSeats} '
                    '${trip.availableSeats == 1 ? 'space' : 'spaces'} left on '
                    'this departure.',
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              // Reserve first, pay on the ticket screen: the space has to be
              // held before there is anything to charge for.
              onPressed: trip.isFull ? null : onBook,
              child: Text(
                trip.isFull ? 'This trip is full' : 'Reserve a space',
              ),
            ),
            if (!trip.isFull) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'You pay on the next screen. The space is held while the '
                'payment is pending.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
