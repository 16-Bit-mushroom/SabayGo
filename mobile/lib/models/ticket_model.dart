import 'uv_trip_model.dart';

enum TicketStatus { active, used, cancelled }

class TicketModel {
  TicketModel({
    required this.ticketId,
    required this.trip,
    required this.passengerName,
    required this.bookingTime,
    required this.qrPayload,
    this.status = TicketStatus.active,
  });

  final String ticketId;
  final UvTripModel trip;
  final String passengerName;
  final DateTime bookingTime;
  final String qrPayload; // Data to generate the QR code
  final TicketStatus status;

  TicketModel copyWith({TicketStatus? status}) {
    return TicketModel(
      ticketId: ticketId,
      trip: trip,
      passengerName: passengerName,
      bookingTime: bookingTime,
      qrPayload: qrPayload,
      status: status ?? this.status,
    );
  }
}