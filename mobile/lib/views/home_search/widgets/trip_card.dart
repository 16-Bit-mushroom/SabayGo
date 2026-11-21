import 'package:flutter/material.dart';

import '../../../core/design/components/app_card.dart';
import '../../../core/design/components/journey_strip.dart';
import '../../../core/design/components/money.dart';
import '../../../core/design/components/status_chip.dart';
import '../../../core/design/tokens.dart';
import '../../../core/util/when.dart';
import '../../../models/uv_trip_model.dart';

/// One departure in the results list.
///
/// Says **seats** (the owner's word since 12 Nov) and never gives one a
/// number: UV Express assigns none, and `seat_number` is an internal slot
/// counter a passenger is never shown.
///
/// Read in the order a person scanning departures asks: when does it
/// leave, and what does it cost -- the two ends of the top line, so both
/// form a column the eye can run down. Then the journey, then how many
/// seats are left and the way in (20 Nov redesign, after Gemini's study).
/// "Leaves in 25 min" appears only within the hour, and "Last trip" only
/// on the day's last departure: a label that is on every card teaches the
/// eye to skip labels.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.onTap});

  final UvTripModel trip;
  final VoidCallback? onTap;

  bool get _scarce => !trip.isFull && (trip.isNearlyFull || trip.occupancyRatio >= 0.8);

  String get _seats => '${trip.availableSeats} ${trip.availableSeats == 1 ? 'seat' : 'seats'}';

  /// "Leaves in 25 min" for a departure within the hour; null otherwise.
  /// A clock comparison, never an estimate.
  String? get _leavesSoon {
    final left = trip.departureTime.difference(DateTime.now());
    if (left.isNegative || left.inMinutes > 60) return null;
    return left.inMinutes < 1 ? 'LEAVES NOW' : 'LEAVES IN ${left.inMinutes} MIN';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A full trip is still worth showing -- it tells someone the 5:30
    // exists and to try the 6:00 -- but it should not compete with the
    // departures they can actually take.
    final anchor = trip.isFull ? AppColors.textMuted : AppColors.textPrimary;
    final eta = trip.estimatedArrivalTime;
    final soon = _leavesSoon;

    return AppCard(
      onTap: onTap,
      semanticLabel: '${semanticSummary()} Opens trip details.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          clockTime(trip.departureTime),
                          style: text.titleLarge!.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: anchor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (soon != null && !trip.isFull) StatusChip(soon, tone: StatusTone.warning),
                        if (trip.isLastTrip) const StatusChip('LAST TRIP', tone: StatusTone.muted),
                      ],
                    ),
                    // No invented arrival: shown only when the server sends one.
                    if (eta != null) Text('Arrives about ${clockTime(eta)}', style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // The fare is exact, from the LTFRB pairwise terminal matrix,
              // so it is not hedged with a "from" or a "~".
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Money(
                    trip.approximateFare,
                    showCentavos: false,
                    style: text.titleLarge!.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: anchor),
                  ),
                  Text('Fixed fare', style: text.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Terminal names, not stop numbers: the same terminal is stop 2 on
          // one route and stop 5 on another.
          JourneyStrip(origin: trip.origin.name, destination: trip.destination.name),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          // A Wrap, so at large text "View details" moves under the chip
          // instead of pushing off the card.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              trip.isFull
                  ? const StatusChip('FULL', tone: StatusTone.danger)
                  : _scarce
                      ? StatusChip('ONLY ${_seats.toUpperCase()} LEFT',
                          tone: StatusTone.warning, icon: Icons.priority_high)
                      : StatusChip('${trip.availableSeats} OF ${trip.totalSeats} SEATS LEFT',
                          tone: StatusTone.success),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trip.isFull ? 'Full' : 'View details',
                    style: text.labelLarge!.copyWith(
                      color: trip.isFull ? AppColors.textMuted : AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!trip.isFull) const Icon(Icons.chevron_right, size: 20, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Read aloud instead of the card's parts, so the spoken row and the
  /// printed row cannot describe different trips.
  String semanticSummary() {
    final availability = trip.isFull
        ? 'full'
        : _scarce
            ? 'only $_seats left'
            : '$_seats left';
    return '${clockTime(trip.departureTime)}, ${trip.origin.name} to '
        '${trip.destination.name}, '
        '${Money.format(trip.approximateFare, showCentavos: false)}, '
        '$availability'
        '${_leavesSoon != null && !trip.isFull ? ', ${_leavesSoon!.toLowerCase()}' : ''}'
        '${trip.isLastTrip ? ', the last trip' : ''}.';
  }
}
