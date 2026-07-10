import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/uv_trip_model.dart';
import '../../viewmodels/ticket_viewmodel.dart';

class TicketScreen extends StatefulWidget {
  final UvTripModel bookedTrip;

  const TicketScreen({super.key, required this.bookedTrip});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late final TicketViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TicketViewModel(bookedTrip: widget.bookedTrip)..addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _viewModel.activeTicket;
    final trip = ticket.trip;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Boarding Pass'),
        backgroundColor: const Color(0xFF2D2059),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // --- THE DIGITAL TICKET ---
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _viewModel.isCancelled ? Colors.red.shade100 : const Color(0xFFE5F6EE),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              trip.operatorName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _viewModel.isCancelled ? Colors.red.shade900 : const Color(0xFF00A859),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _viewModel.isCancelled ? 'CANCELLED' : 'CONFIRMED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _viewModel.isCancelled ? Colors.red.shade900 : const Color(0xFF00A859),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // QR Code Area
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Opacity(
                            opacity: _viewModel.isCancelled ? 0.3 : 1.0,
                            child: const Icon(Icons.qr_code_2, size: 120, color: Color(0xFF2D2059)),
                          ),
                          const SizedBox(height: 12),
                          Text('Ticket ID: ${ticket.ticketId}', style: const TextStyle(letterSpacing: 1.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Present this to the dispatcher', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    
                    // Divider with cutouts
                    Row(
                      children: [
                        Container(height: 20, width: 10, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)))),
                        Expanded(child: LayoutBuilder(builder: (context, constraints) {
                          return Flex(
                            direction: Axis.horizontal,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate((constraints.constrainWidth() / 10).floor(), (index) => const SizedBox(width: 5, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey)))),
                          );
                        })),
                        Container(height: 20, width: 10, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)))),
                      ],
                    ),

                    // Trip Info with Icons
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildInfoRow(Icons.person_outline, 'Passenger', ticket.passengerName),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.access_time_outlined, 'Booked On', DateFormat('MMM dd, yyyy - hh:mm a').format(ticket.bookingTime)),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(),
                          ),
                          
                          _buildInfoRow(Icons.trip_origin, 'Origin', trip.origin.name, iconColor: const Color(0xFF00A859)),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.location_on, 'Destination', trip.destination.name, iconColor: const Color(0xFFD9534F)),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.departure_board, 'Departure', _formatTime(trip.departureTime)),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.flag_outlined, 'Est. Arrival', _formatTime(trip.estimatedArrivalTime)),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(),
                          ),
                          
                          _buildInfoRow(Icons.payments_outlined, 'Approx. Fare', '₱${trip.approximateFare.toStringAsFixed(0)}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Cancel Button
              if (!_viewModel.isCancelled)
                TextButton.icon(
                  onPressed: () {
                    _viewModel.cancelTicket();
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text('Cancel Reservation', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? iconColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor ?? Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value, 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return DateFormat('hh:mm a').format(dt);
  }
}