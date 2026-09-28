import 'package:flutter/material.dart';
import '../../../models/uv_trip_model.dart';
import 'package:intl/intl.dart';
import '../../../core/design/tokens.dart';

class TripDetailsSheet extends StatelessWidget {
  final UvTripModel trip;
  final VoidCallback onBook;

  const TripDetailsSheet({super.key, required this.trip, required this.onBook});

  String _formatTime(DateTime dt) => DateFormat('hh:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = trip.estimatedArrivalTime;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Drag Handle ---
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            
            // --- Header & Fare ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.tripLabel, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(trip.operatorName ?? trip.plateNumber ?? "—", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${trip.approximateFare.toStringAsFixed(2)}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    Text('Fare', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 24),

            // --- The Route & Schedule Timeline ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.infoContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.info),
              ),
              child: Column(
                children: [
                  _buildTimelineRow(
                    time: _formatTime(trip.departureTime),
                    location: trip.origin.name,
                    label: 'Departure',
                    iconColor: AppColors.success,
                    isLast: false,
                  ),
                  _buildTimelineRow(
                    time: eta == null ? '—' : _formatTime(eta),
                    location: trip.destination.name,
                    label: 'Arrives about',
                    iconColor: AppColors.danger,
                    isLast: true,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // --- Vehicle Details ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vehicle', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.directions_car, 'Vehicle Type', 'UV Express'),
                  const Divider(height: 20),
                  _buildDetailRow(Icons.pin, 'Plate Number', trip.plateNumber ?? '—'),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // --- Seat Status ---
            Row(
              children: [
                // Not a seat icon: UV Express assigns no seat numbers, and
                // a diagram of a seat implies a reserved position in the
                // van that the passenger does not get.
                Icon(Icons.groups_outlined,
                    color: trip.isFull ? AppColors.danger : AppColors.success),
                const SizedBox(width: 8),
                Text(
                  trip.isFull
                      ? 'No spaces left on this trip'
                      : '${trip.availableSeats} of ${trip.totalSeats} spaces left',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: trip.isFull
                          ? AppColors.danger
                          : AppColors.success,
                      fontSize: 16),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // --- Full Width Reservation Button ---
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                // Reserve first, pay on the ticket screen: the space has
                // to be held before there is anything to charge for.
                onPressed: trip.isFull ? null : onBook,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                    trip.isFull ? 'This trip is full' : 'Reserve a space'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow({required String time, required String location, required String label, required Color iconColor, required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        Column(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconColor),
            ),
            if (!isLast)
              Container(
                width: 2, height: 30,
                color: AppColors.divider,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(location, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (!isLast) const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textMuted)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}