import 'package:flutter/foundation.dart';
import '../models/ticket_model.dart';
import '../models/uv_trip_model.dart';

class TicketViewModel extends ChangeNotifier {
  TicketViewModel({required UvTripModel bookedTrip}) {
    // Mocking the ticket generation that would normally happen on your Python backend
    _activeTicket = TicketModel(
      ticketId: 'TXN-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
      trip: bookedTrip,
      passengerName: 'Sarah K.', // Hardcoded for prototype
      bookingTime: DateTime.now(),
      qrPayload: 'sabaygo://verify/${bookedTrip.id}/user123',
    );
  }

  late TicketModel _activeTicket;
  TicketModel get activeTicket => _activeTicket;

  bool get isCancelled => _activeTicket.status == TicketStatus.cancelled;

  void cancelTicket() {
    _activeTicket = _activeTicket.copyWith(status: TicketStatus.cancelled);
    // TODO: Send cancellation to FastAPI backend to free up the seat inventory
    notifyListeners();
  }
}