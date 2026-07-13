import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/uv_trip_model.dart';

// --- Local Enums & Models for UI State ---
enum PassengerState { pending, boarded, cancelled }
enum BookingType { app, walkIn }

class ManifestPassenger {
  final String id;
  final String name;
  final String ticketId;
  final BookingType type;
  PassengerState state;

  ManifestPassenger({
    required this.id,
    required this.name,
    required this.ticketId,
    required this.type,
    this.state = PassengerState.pending,
  });
}

class TripManifestScreen extends StatefulWidget {
  final UvTripModel trip;

  const TripManifestScreen({super.key, required this.trip});

  @override
  State<TripManifestScreen> createState() => _TripManifestScreenState();
}

class _TripManifestScreenState extends State<TripManifestScreen> {
  late UvTripModel _currentTrip;
  late List<ManifestPassenger> _passengers;

  @override
  void initState() {
    super.initState();
    _currentTrip = widget.trip;
    
    // Initialize mock passenger list
    _passengers = [
      ManifestPassenger(id: 'p1', name: 'Sarah K. Dela Cruz', ticketId: 'TXN-88492', type: BookingType.app, state: PassengerState.boarded),
      ManifestPassenger(id: 'p2', name: 'Juan Miguel Santos', ticketId: 'TXN-88493', type: BookingType.app, state: PassengerState.pending),
      ManifestPassenger(id: 'p3', name: 'Maria Clara', ticketId: 'TXN-88494', type: BookingType.app, state: PassengerState.pending),
    ];
    
    _recalculateSeats();
  }

  void _recalculateSeats() {
    // Only pending and boarded passengers consume a seat.
    final activeCount = _passengers.where((p) => p.state != PassengerState.cancelled).length;
    setState(() {
      _currentTrip = _currentTrip.copyWith(availableSeats: _currentTrip.totalSeats - activeCount);
    });
  }

  // --- Actions ---

  void _updateTripStatus(TripStatus newStatus) {
    if (newStatus == TripStatus.departed) {
      _handleDeparture();
      return;
    }

    setState(() => _currentTrip = _currentTrip.copyWith(status: newStatus));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Van status updated to ${newStatus.name.toUpperCase()}')),
    );
  }

  void _handleDeparture() {
    final pendingCount = _passengers.where((p) => p.state == PassengerState.pending).length;

    if (pendingCount > 0) {
      // Warn dispatcher about leaving passengers behind
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Depart Incomplete?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('There are $pendingCount passengers who have not boarded yet. Departing now will cancel their reservations and notify them that the trip has left. Proceed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _executeDeparture();
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD9534F)),
              child: const Text('Confirm Departure'),
            ),
          ],
        ),
      );
    } else {
      _executeDeparture();
    }
  }

  void _executeDeparture() {
    setState(() {
      _currentTrip = _currentTrip.copyWith(status: TripStatus.departed);
      // Auto-cancel any remaining pending passengers
      for (var p in _passengers) {
        if (p.state == PassengerState.pending) {
          p.state = PassengerState.cancelled;
        }
      }
    });
    _recalculateSeats();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip marked as DEPARTED. Notifications sent.')),
    );
  }

  void _updatePassengerState(ManifestPassenger passenger, PassengerState newState) {
    setState(() {
      passenger.state = newState;
    });
    _recalculateSeats();
  }

  void _addMockWalkIn() {
    if (_currentTrip.availableSeats <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Van is fully booked!')));
      return;
    }

    setState(() {
      _passengers.add(ManifestPassenger(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Walk-in Passenger',
        ticketId: 'WLK-${DateTime.now().second}${DateTime.now().minute}',
        type: BookingType.walkIn,
        state: PassengerState.boarded, // Walk-ins are automatically boarded
      ));
    });
    _recalculateSeats();
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    final int occupiedSeats = _currentTrip.totalSeats - _currentTrip.availableSeats;
    final bool isDeparted = _currentTrip.status == TripStatus.departed;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(_currentTrip.tripLabel, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          // Simulated QR Scanner trigger for testing
          if (!isDeparted)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00A859)),
              tooltip: 'Simulate Scan',
              onPressed: () {
                final pending = _passengers.where((p) => p.state == PassengerState.pending).toList();
                if (pending.isNotEmpty) {
                  _updatePassengerState(pending.first, PassengerState.boarded);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pending.first.name} Scanned & Boarded!')));
                }
              },
            ),
        ],
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
                        Text('$occupiedSeats / ${_currentTrip.totalSeats}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _currentTrip.availableSeats == 0 ? Colors.red : Colors.black87)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _passengers.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _buildPassengerTile(_passengers[index], isDeparted);
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
      bottomNavigationBar: isDeparted 
        ? null 
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _addMockWalkIn, // In a real app, opens the Walk-in Form Modal
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
        onTap: () => _updateTripStatus(status),
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

  Widget _buildPassengerTile(ManifestPassenger passenger, bool isDeparted) {
    Color statusColor;
    String statusText;

    switch (passenger.state) {
      case PassengerState.pending:
        statusColor = Colors.orange;
        statusText = 'NOT YET';
        break;
      case PassengerState.boarded:
        statusColor = Colors.green;
        statusText = 'BOARDED';
        break;
      case PassengerState.cancelled:
        statusColor = Colors.red;
        statusText = 'CANCELLED';
        break;
    }

    final isWalkIn = passenger.type == BookingType.walkIn;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey.shade100,
        child: Icon(isWalkIn ? Icons.hail : Icons.phone_android, color: Colors.grey.shade500, size: 20),
      ),
      title: Text(
        passenger.name, 
        style: TextStyle(
          fontWeight: FontWeight.bold, 
          decoration: passenger.state == PassengerState.cancelled ? TextDecoration.lineThrough : null,
          color: passenger.state == PassengerState.cancelled ? Colors.grey : Colors.black87
        ),
      ),
      subtitle: Text(
        '${passenger.ticketId} • ${isWalkIn ? 'Walk-in' : 'App Booking'}', 
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1), 
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          
          // Only show manual override menu if trip is active and ticket is not cancelled
          if (!isDeparted && passenger.state != PassengerState.cancelled)
            PopupMenuButton<PassengerState>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (newState) => _updatePassengerState(passenger, newState),
              itemBuilder: (context) {
                return [
                  if (passenger.state == PassengerState.pending)
                    const PopupMenuItem(value: PassengerState.boarded, child: Text('Manual Check-in')),
                  const PopupMenuItem(value: PassengerState.cancelled, child: Text('Cancel / No-Show', style: TextStyle(color: Colors.red))),
                ];
              },
            ),
        ],
      ),
    );
  }
}