import 'package:flutter/material.dart';
import '../../../models/uv_trip_model.dart';

class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.onBook,
  });

  final UvTripModel trip;
  final VoidCallback onBook;

  Color _seatColor(BuildContext context) {
    if (trip.isFull) return Theme.of(context).colorScheme.error;
    if (trip.occupancyRatio >= 0.8) return Colors.orange;
    return Colors.green;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(trip.departureTime),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    trip.tripLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trip.origin.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward, size: 14),
                      ),
                      Flexible(
                        child: Text(
                          trip.destination.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trip.operatorName,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _seatColor(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      trip.isFull
                          ? 'Full'
                          : '${trip.availableSeats}/${trip.totalSeats} seats left',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _seatColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: trip.isFull ? null : onBook,
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(trip.isFull ? 'Full' : 'Book'),
            ),
          ],
        ),
      ),
    );
  }
}
