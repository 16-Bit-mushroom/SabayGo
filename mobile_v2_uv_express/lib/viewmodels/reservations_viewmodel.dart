import 'package:flutter/material.dart';
import '../models/ticket_model.dart';
import '../models/uv_trip_model.dart';
import '../models/transit_node_model.dart';

class ReservationsViewModel extends ChangeNotifier {
  ReservationsViewModel() {
    _loadMockData();
  }

  TicketModel? activeTicket;
  List<TicketModel> historyTickets = [];
  List<TicketModel> cancelledTickets = [];

  void _loadMockData() {
    final today = DateTime.now();
    
    // Mock Nodes
    const davao = TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City');
    const cotabato = TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City');
    const tagum = TransitNodeModel(id: 'n5', name: 'Tagum City Terminal', area: 'Tagum City');

    // Mock Active Ticket
    final activeTrip = UvTripModel(
      id: 't1',
      tripLabel: 'Afternoon Run',
      departureTime: today.add(const Duration(hours: 2)),
      estimatedArrivalTime: today.add(const Duration(hours: 3, minutes: 30)),
      origin: davao,
      destination: tagum,
      totalSeats: 18,
      availableSeats: 5,
      operatorName: 'Metro Davao Vans',
      approximateFare: 150.0,
    );

    activeTicket = TicketModel(
      ticketId: 'TXN-88492',
      trip: activeTrip,
      passengerName: 'Sarah K.',
      bookingTime: today.subtract(const Duration(minutes: 45)),
      qrPayload: 'sabaygo://verify/t1/user123',
      status: TicketStatus.active,
    );

    // Mock History Ticket
    final pastTrip = UvTripModel(
      id: 't2',
      tripLabel: 'Morning Express',
      departureTime: today.subtract(const Duration(days: 2, hours: 5)),
      estimatedArrivalTime: today.subtract(const Duration(days: 2, hours: 0)),
      origin: davao,
      destination: cotabato,
      totalSeats: 18,
      availableSeats: 0,
      operatorName: 'RDT Transport',
      approximateFare: 500.0,
      status: TripStatus.departed,
    );

    historyTickets.add(
      TicketModel(
        ticketId: 'TXN-11204',
        trip: pastTrip,
        passengerName: 'Sarah K.',
        bookingTime: today.subtract(const Duration(days: 3)),
        qrPayload: 'sabaygo://verify/t2/user123',
        status: TicketStatus.used,
      ),
    );

    // Mock Cancelled Ticket
    final cancelledTrip = UvTripModel(
      id: 't3',
      tripLabel: 'Noon Trip',
      departureTime: today.subtract(const Duration(days: 5, hours: 2)),
      estimatedArrivalTime: today.subtract(const Duration(days: 5, hours: 0)),
      origin: tagum,
      destination: davao,
      totalSeats: 14,
      availableSeats: 14,
      operatorName: 'Metro Davao Vans',
      approximateFare: 150.0,
    );

    cancelledTickets.add(
      TicketModel(
        ticketId: 'TXN-99381',
        trip: cancelledTrip,
        passengerName: 'Sarah K.',
        bookingTime: today.subtract(const Duration(days: 6)),
        qrPayload: 'sabaygo://verify/t3/user123',
        status: TicketStatus.cancelled,
      ),
    );

    notifyListeners();
  }
}