import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../models/uv_trip_model.dart';

/// One departure in the results list.
///
/// Says **spaces**, never "seats". UV Express does not assign seat numbers —
/// capacity is counted per leg, and `seat_number` is an internal slot
/// counter a passenger is never shown. A card promising a seat promises
/// something the system does not sell.
///
/// Availability was coloured with `Colors.green` (2.8:1 on white) and
/// `Colors.orange` (2.2:1). That number is the single most important thing
/// on the card and it was the least readable. It now uses the verified
/// tokens, and scarcity is stated in words as well as hue, because a
/// passenger who cannot distinguish the two still needs to know the van is
/// nearly full.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip});

  final UvTripModel trip;

  /// How close to full, as a tone rather than a colour.
  ({Color fg, Color bg, String note}) _availability() {
    if (trip.isFull) {
      return (
        fg: AppColors.danger,
        bg: AppColors.dangerContainer,
        note: 'Full',
      );
    }
    if (trip.occupancyRatio >= 0.8) {
      return (
        fg: AppColors.warning,
        bg: AppColors.warningContainer,
        note: 'Almost full',
      );
    }
    return (
      fg: AppColors.success,
      bg: AppColors.successContainer,
      note: 'Available',
    );
  }

  String _time(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = _availability();

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Departure time leads, because that is what people scan a
            // results list for. No fixed width: a 95px box clipped the time
            // as soon as the system font scaled up.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _time(trip.departureTime),
                  style: text.titleMedium!.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(trip.tripLabel, style: text.bodySmall),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Terminal names, not stop numbers. The same terminal is
                  // stop 2 on one route and stop 5 on another, so a number
                  // here would mean nothing to a passenger.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trip.origin.name,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs + 1),
                        child: Icon(Icons.arrow_forward,
                            size: 13, color: AppColors.textMuted),
                      ),
                      Flexible(
                        child: Text(
                          trip.destination.name,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    trip.plateNumber ?? trip.operatorName ?? '—',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Fare and remaining space, the two things a passenger chooses
            // on. The fare is exact, from the LTFRB pairwise terminal
            // matrix -- not an estimate, so it is not hedged.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${trip.approximateFare.toStringAsFixed(0)}',
                  style: text.titleLarge!.copyWith(
                    color: AppColors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: a.bg,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    trip.isFull
                        ? 'Full'
                        : '${trip.availableSeats} ${trip.availableSeats == 1
                            ? 'space'
                            : 'spaces'}',
                    style: text.labelSmall!.copyWith(color: a.fg),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Read aloud by the parent row, which owns the tap. Kept here so the
  /// sentence and the card cannot describe different things.
  String semanticSummary() {
    final a = _availability();
    return '${_time(trip.departureTime)}, ${trip.origin.name} to '
        '${trip.destination.name}, '
        '₱${trip.approximateFare.toStringAsFixed(0)}, '
        '${trip.isFull ? 'full' : '${trip.availableSeats} spaces left'}'
        '. ${a.note}.';
  }
}
