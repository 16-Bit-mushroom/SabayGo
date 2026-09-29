import 'package:flutter/material.dart';

import '../../../core/design/components/app_card.dart';
import '../../../core/design/components/money.dart';
import '../../../core/design/components/status_chip.dart';
import '../../../core/design/tokens.dart';
import '../../../core/util/when.dart';
import '../../../models/uv_trip_model.dart';

/// One departure in the results list.
///
/// Says **spaces**, never "seats". UV Express does not assign seat numbers —
/// capacity is counted per leg, and `seat_number` is an internal slot
/// counter a passenger is never shown. A card promising a seat promises
/// something the system does not sell.
///
/// Recomposed from three columns of equal weight — time, route, fare — which
/// gave the eye no order to read them in. A person scanning a list of
/// departures is answering two questions, in this order: when does it leave,
/// and what does it cost. Those two now sit on one line at the top, at the
/// two ends, so both form a column the eye can run down. The journey sits
/// under them, and the van and the remaining space sit quietly at the
/// bottom.
///
/// Availability is a chip **only when it is scarce**. Twelve green
/// "Available" chips down a list is twelve pieces of decoration teaching the
/// eye to ignore chips, which is exactly the wrong lesson for the one row
/// that says "Only 2 left". Ordinary availability is plain muted text.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.onTap});

  final UvTripModel trip;
  final VoidCallback? onTap;

  bool get _scarce =>
      !trip.isFull && (trip.isNearlyFull || trip.occupancyRatio >= 0.8);

  String get _spaces =>
      '${trip.availableSeats} ${trip.availableSeats == 1 ? 'space' : 'spaces'}';

  /// Short on purpose. At 200% text on a 320dp phone this chip, the van's
  /// plate and an icon share one row, and "ONLY 2 SPACES LEFT" overflowed it
  /// by 28 pixels. The full sentence is still spoken — see
  /// [semanticSummary] — so nothing is lost by abbreviating the glance form.
  String get _shortSpaces => '${trip.availableSeats} LEFT';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // A full trip is still worth showing — it tells someone the 5:30 exists
    // and to try the 6:00 — but it should not compete with the departures
    // they can actually take.
    final anchor = trip.isFull ? AppColors.textMuted : AppColors.textPrimary;
    final fare = trip.isFull ? AppColors.textMuted : AppColors.primary;

    return AppCard(
      onTap: onTap,
      semanticLabel: '${semanticSummary()} Opens trip details.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier one: when, and how much.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  clockTime(trip.departureTime),
                  style: text.titleLarge!.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: anchor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // The fare is exact, from the LTFRB pairwise terminal matrix,
              // so it is not hedged with a "from" or a "~".
              Money(
                trip.approximateFare,
                showCentavos: false,
                style: text.titleLarge!.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: fare,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Tier two: the journey. Terminal names, not stop numbers — the
          // same terminal is stop 2 on one route and stop 5 on another, so a
          // number here would mean nothing to a passenger.
          Row(
            children: [
              Flexible(
                child: Text(
                  trip.origin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(Icons.arrow_forward,
                    size: 14, color: AppColors.textMuted),
              ),
              Flexible(
                child: Text(
                  trip.destination.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Tier three: which van, and what is left.
          Row(
            children: [
              const Icon(Icons.airport_shuttle_outlined,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: Text(
                  trip.plateNumber ?? trip.operatorName ?? trip.tripLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Flexible, because a chip left inflexible in a Row is handed
              // unbounded width: it then sizes to its text and pushes
              // everything beside it off the card instead of ellipsising.
              Flexible(
                child: trip.isFull
                    ? const StatusChip('FULL', tone: StatusTone.danger)
                    : _scarce
                        ? StatusChip(
                            _shortSpaces,
                            tone: StatusTone.warning,
                            icon: Icons.priority_high,
                          )
                        : Text(
                            _spaces,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
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
            ? 'only $_spaces left'
            : '$_spaces left';
    return '${clockTime(trip.departureTime)}, ${trip.origin.name} to '
        '${trip.destination.name}, '
        '${Money.format(trip.approximateFare, showCentavos: false)}, '
        '$availability.';
  }
}
