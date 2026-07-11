import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/uv_trip_model.dart';

class TripManifestScreen extends StatefulWidget {
  final UvTripModel trip;

  const TripManifestScreen({super.key, required this.trip});

  @override
  State<TripManifestScreen> createState() => _TripManifestScreenState();
}

class _TripManifestScreenState extends State<TripManifestScreen> {
  late UvTripModel _currentTrip;

  @override
  void initState() {
    super.initState();
    _currentTrip = widget.trip;
  }

  void _updateStatus(TripStatus newStatus) {
    setState(() {
      _currentTrip = _currentTrip.copyWith(status: newStatus);
    });
    // TODO: Send update to backend to notify passengers
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Van status updated to ${newStatus.name.toUpperCase()}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(_currentTrip.tripLabel, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Column(
        children: [
          // --- Trip Status Control Panel ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TRIP STATUS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    Text(
                      DateFormat('MMM dd • hh:mm a').format(_currentTrip.departureTime),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatusButton('Boarding', TripStatus.boarding, Colors.green),
                    const SizedBox(width: 8),
                    _buildStatusButton('Full', TripStatus.full, Colors.orange),
                    const SizedBox(width: 8),
                    _buildStatusButton('Departed', TripStatus.departed, Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),

          // --- Passenger Manifest ---
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('PASSENGER MANIFEST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                        Text('${_currentTrip.totalSeats - _currentTrip.availableSeats} / ${_currentTrip.totalSeats}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: 3, // Mock count for now
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey.shade200,
                            child: const Icon(Icons.person, color: Colors.grey),
                          ),
                          title: const Text('Sarah K. Dela Cruz', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Ticket: TXN-88492 • App Booking', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                            child: const Text('BOARDED', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
      // --- Add Walk-in Button ---
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () {
              // TODO: Open Add Walk-in Bottom Sheet
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00A859),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Walk-in Passenger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusButton(String label, TripStatus status, Color color) {
    final bool isActive = _currentTrip.status == status;
    return Expanded(
      child: InkWell(
        onTap: () => _updateStatus(status),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white,
            border: Border.all(color: isActive ? color : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}