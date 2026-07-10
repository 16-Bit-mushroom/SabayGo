import 'package:flutter/material.dart';
import '../../../models/uv_trip_model.dart';
import 'package:intl/intl.dart';

class TripDetailsSheet extends StatelessWidget {
  final UvTripModel trip;
  final VoidCallback onBook;

  const TripDetailsSheet({super.key, required this.trip, required this.onBook});

  String _formatTime(DateTime dt) => DateFormat('hh:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // MOCK DATA: Replace these with actual properties from your UvTripModel later!
    final DateTime eta = trip.departureTime.add(const Duration(hours: 2)); 
    const double approxFare = 150.00;

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
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
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
                    Text(trip.operatorName, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${approxFare.toStringAsFixed(0)}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF00A859))),
                    Text('Approx. Fare', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 24),

            // --- The Route & Schedule Timeline ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                children: [
                  _buildTimelineRow(
                    time: _formatTime(trip.departureTime),
                    location: trip.origin.name,
                    label: 'Departure',
                    iconColor: const Color(0xFF00A859), // Green for Origin
                    isLast: false,
                  ),
                  _buildTimelineRow(
                    time: _formatTime(eta),
                    location: trip.destination.name,
                    label: 'Est. Arrival',
                    iconColor: const Color(0xFFD9534F), // Red for Destination
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
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('VEHICLE DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.grey)),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.directions_car, 'Vehicle Type', 'Toyota Hiace Commuter'), // Mocked
                  const Divider(height: 20),
                  _buildDetailRow(Icons.pin, 'Plate Number', 'DVO-1234'), // Mocked
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // --- Seat Status ---
            Row(
              children: [
                Icon(Icons.event_seat, color: trip.isFull ? Colors.red : Colors.green),
                const SizedBox(width: 8),
                Text(
                  trip.isFull ? 'No seats available' : '${trip.availableSeats} out of ${trip.totalSeats} seats left',
                  style: TextStyle(fontWeight: FontWeight.bold, color: trip.isFull ? Colors.red : Colors.green, fontSize: 16),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // --- Full Width Book Button ---
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: trip.isFull ? null : () {
                  Navigator.pop(context); // Close sheet
                  onBook(); // Trigger booking
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A859),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(trip.isFull ? 'TRIP FULL' : 'RESERVE SEAT', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper Widget for the Route Timeline
  Widget _buildTimelineRow({required String time, required String location, required String label, required Color iconColor, required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time Column
        SizedBox(
          width: 70,
          child: Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        // Timeline Visual Column
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconColor),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30, // Height of the connecting line
                color: Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        // Location Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(location, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              if (!isLast) const SizedBox(height: 16), // Spacing below the first item
            ],
          ),
        ),
      ],
    );
  }

  // Helper Widget for Vehicle Details
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}