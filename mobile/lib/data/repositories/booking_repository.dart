import '../../core/network/api_client.dart';

/// A booking as the passenger sees it.
///
/// No seat number: UV Express does not assign seats. The system counts
/// how much space is taken on each section of road so a van is never
/// oversold, but nobody is told where to sit.
class BookingSummary {
  const BookingSummary({
    required this.bookingId,
    required this.ticketNumber,
    required this.tripId,
    required this.departure,
    required this.routeName,
    required this.boardingStop,
    required this.alightingStop,
    required this.fare,
    required this.status,
    required this.canReschedule,
    this.qrPayload,
    this.rescheduleDeadline,
  });

  final String bookingId;
  final String ticketNumber;
  final String tripId;
  final DateTime departure;
  final String routeName;
  final int boardingStop;
  final int alightingStop;
  final double fare;
  final String status;
  final String? qrPayload;

  /// Computed by the server from the trip's own snapshot of the policy,
  /// so the app does not reimplement the rule. The server checks again
  /// on the actual request — this only decides whether to offer it.
  final bool canReschedule;
  final DateTime? rescheduleDeadline;

  bool get isAwaitingPayment => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCheckedIn => status == 'checked_in';
  bool get isBoarded => status == 'boarded';
  bool get isCancelled => status == 'cancelled';
  bool get isActive =>
      isAwaitingPayment || isConfirmed || isCheckedIn || isBoarded;

  /// The e-ticket is only meaningful once the fare has settled.
  bool get hasUsableTicket => qrPayload != null && !isAwaitingPayment;

  String get statusLabel => switch (status) {
        'pending' => 'Awaiting payment',
        'confirmed' => 'Confirmed',
        'checked_in' => 'Checked in',
        'boarded' => 'On board',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'no_show' => 'Missed',
        'rescheduled' => 'Moved',
        _ => status,
      };

  factory BookingSummary.fromJson(Map<String, dynamic> j) => BookingSummary(
        bookingId: j['booking_id'] as String,
        ticketNumber: j['ticket_number'] as String,
        tripId: j['trip_id'] as String,
        departure: DateTime.parse(j['departure_datetime'] as String),
        routeName: j['route_name'] as String? ?? '',
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        fare: double.parse(j['fare_amount'].toString()),
        status: j['status'] as String,
        qrPayload: j['qr_payload'] as String?,
        canReschedule: j['can_reschedule'] as bool? ?? false,
        rescheduleDeadline: j['reschedule_deadline'] == null
            ? null
            : DateTime.parse(j['reschedule_deadline'] as String),
      );
}

/// The result of claiming space. Returned by reserve, before payment.
class ReservationResult {
  const ReservationResult({
    required this.bookingId,
    required this.ticketNumber,
    required this.fare,
    required this.status,
    this.qrPayload,
  });

  final String bookingId;
  final String ticketNumber;
  final double fare;
  final String status;
  final String? qrPayload;

  factory ReservationResult.fromJson(Map<String, dynamic> j) =>
      ReservationResult(
        bookingId: j['booking_id'] as String,
        ticketNumber: j['ticket_number'] as String,
        fare: double.parse(j['fare_amount'].toString()),
        status: j['status'] as String,
        qrPayload: j['qr_payload'] as String?,
      );
}

class BookingRepository {
  BookingRepository(this._api);
  final ApiClient _api;

  /// Claim space for a journey.
  ///
  /// Runs the server's pessimistic lock. Two outcomes are worth telling
  /// apart, and the exception types do: a 409 means genuinely sold out
  /// and retrying is pointless, while a 503 means the request lost a race
  /// for the lock and retrying will probably succeed.
  ///
  /// The space is held for ten minutes pending payment, then released.
  Future<ReservationResult> reserve({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
  }) async {
    final json = await _api.post('/bookings/reserve', body: {
      'trip_id': tripId,
      'boarding_stop': boardingStop,
      'alighting_stop': alightingStop,
    });
    return ReservationResult.fromJson(json as Map<String, dynamic>);
  }

  Future<List<BookingSummary>> mine() async {
    final json = await _api.get('/bookings/mine') as List<dynamic>;
    return json
        .map((e) => BookingSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Move a booking to another departure on the same route.
  ///
  /// The journey stays the same — only the trip changes. Allowing the
  /// journey to change would mean handling fare differences, which under
  /// a no-refund policy has no sensible answer when the new journey is
  /// cheaper.
  Future<String> reschedule({
    required String bookingId,
    required String newTripId,
  }) async {
    final json = await _api.post(
      '/bookings/$bookingId/reschedule',
      body: {'new_trip_id': newTripId},
    ) as Map<String, dynamic>;
    return json['new_booking_id'] as String;
  }

  /// Cancel and release the space. No refund is issued.
  Future<void> cancel(String bookingId) =>
      _api.post('/bookings/$bookingId/cancel');

  /// Start a PayMongo checkout. Returns the URL to open.
  ///
  /// Opening it is only half the flow: the booking is confirmed by a
  /// signed webhook from the payment provider, never by the app
  /// returning from the browser. A client that reports success can be
  /// replayed, faked, or simply lost when someone closes the tab.
  Future<String> startCheckout(String bookingId) async {
    final json = await _api.post(
      '/payments/checkout',
      body: {'booking_id': bookingId},
    ) as Map<String, dynamic>;
    return json['checkout_url'] as String;
  }

  /// Confirm presence at the boarding terminal.
  ///
  /// The app sends a position; the server decides. An app that judged
  /// its own geofence could report success from anywhere.
  Future<Map<String, dynamic>> checkIn({
    required String bookingId,
    required double latitude,
    required double longitude,
    double? accuracyM,
  }) async {
    final json = await _api.post('/bookings/$bookingId/check-in', body: {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyM != null) 'gps_accuracy_m': accuracyM,
    });
    return json as Map<String, dynamic>;
  }
}