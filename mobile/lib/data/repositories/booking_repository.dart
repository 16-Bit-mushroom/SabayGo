import 'dart:typed_data';

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
    required this.routeId,
    required this.routeName,
    required this.boardingStop,
    required this.alightingStop,
    required this.boardingTerminal,
    required this.alightingTerminal,
    required this.fare,
    required this.status,
    required this.canReschedule,
    this.qrPayload,
    this.rescheduleDeadline,
    this.boardingDueAt,
    this.checkinOpensAt,
    this.homePickup,
  });

  final String bookingId;
  final String ticketNumber;
  final String tripId;
  final DateTime departure;
  final String routeId;
  final String routeName;
  final int boardingStop;
  final int alightingStop;
  final String boardingTerminal;
  final String alightingTerminal;
  final double fare;
  final String status;
  final String? qrPayload;

  /// Computed by the server from the trip's own snapshot of the policy,
  /// so the app does not reimplement the rule. The server checks again
  /// on the actual request — this only decides whether to offer it.
  final bool canReschedule;
  final DateTime? rescheduleDeadline;

  /// When the van is due at *this passenger's* boarding stop, and when
  /// check-in there opens. Computed server-side from the stop's offset
  /// on the route; a stop-3 passenger is not at the origin at departure.
  final DateTime? boardingDueAt;
  final DateTime? checkinOpensAt;

  /// Set when this is one of a home pickup's two seats (brief 2.6).
  final HomePickupRef? homePickup;

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
        routeId: j['route_id'] as String? ?? '',
        routeName: j['route_name'] as String? ?? '',
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        boardingTerminal: j['boarding_terminal'] as String? ?? '',
        alightingTerminal: j['alighting_terminal'] as String? ?? '',
        fare: double.parse(j['fare_amount'].toString()),
        status: j['status'] as String,
        qrPayload: j['qr_payload'] as String?,
        canReschedule: j['can_reschedule'] as bool? ?? false,
        rescheduleDeadline: j['reschedule_deadline'] == null
            ? null
            : DateTime.parse(j['reschedule_deadline'] as String),
        boardingDueAt: j['boarding_due_at'] == null
            ? null
            : DateTime.parse(j['boarding_due_at'] as String),
        checkinOpensAt: j['checkin_opens_at'] == null
            ? null
            : DateTime.parse(j['checkin_opens_at'] as String),
        homePickup: j['home_pickup'] == null
            ? null
            : HomePickupRef.fromJson(j['home_pickup'] as Map<String, dynamic>),
      );
}

/// The home pickup a booking belongs to: the passenger's seat boards at
/// the pin, the relative's at the terminal.
class HomePickupRef {
  const HomePickupRef({
    required this.pickupId,
    required this.beneficiaryName,
    required this.isPassengerSeat,
    required this.proofSent,
    required this.proofConfirmed,
  });

  final String pickupId;
  final String beneficiaryName;
  final bool isPassengerSeat;
  final bool proofSent;
  final bool proofConfirmed;

  factory HomePickupRef.fromJson(Map<String, dynamic> j) => HomePickupRef(
        pickupId: j['pickup_id'] as String,
        beneficiaryName: j['beneficiary_name'] as String,
        isPassengerSeat: j['is_passenger_seat'] as bool,
        proofSent: j['proof_sent'] as bool,
        proofConfirmed: j['proof_confirmed'] as bool,
      );
}

/// The two seats of a home pickup, just booked.
class HomePickupBooking {
  const HomePickupBooking({required this.pickupId, required this.relative, required this.passenger});
  final String pickupId;
  final ReservationResult relative;
  final ReservationResult passenger;
}

/// What the booking screen says about the camera (brief 4.5), from A2Z's
/// settings in force.
class PrivacyNotice {
  const PrivacyNotice({
    required this.retentionDays,
    required this.chatImageRetentionDays,
    required this.chatImageMaxKb,
    required this.privacyContact,
  });

  final int? retentionDays;
  final int chatImageRetentionDays;
  final int chatImageMaxKb;
  final String privacyContact;

  factory PrivacyNotice.fromJson(Map<String, dynamic> j) => PrivacyNotice(
        retentionDays: j['retention_days'] as int?,
        chatImageRetentionDays: j['chat_image_retention_days'] as int,
        chatImageMaxKb: j['chat_image_max_kb'] as int,
        privacyContact: j['privacy_contact'] as String,
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

  /// One of the caller's own bookings, same shape as an element of [mine].
  /// The ticket screen polls this while a checkout is pending (G.7).
  Future<BookingSummary> byId(String bookingId) async {
    final json = await _api.get('/bookings/$bookingId');
    return BookingSummary.fromJson(json as Map<String, dynamic>);
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
  /// Book for someone else (brief 2.6): the relative's seat and the
  /// passenger's, from the starting terminal to one drop-off, in one go.
  /// Both are paid one by one, like any booking.
  Future<HomePickupBooking> bookHomePickup({
    required String tripId,
    required int alightingStop,
    required String name,
    required String contact,
    required double latitude,
    required double longitude,
    String? note,
  }) async {
    final json = await _api.post('/home-pickups', body: {
      'trip_id': tripId,
      'alighting_stop': alightingStop,
      'beneficiary_name': name,
      'beneficiary_contact': contact,
      'pickup_latitude': latitude.toStringAsFixed(6),
      'pickup_longitude': longitude.toStringAsFixed(6),
      if (note != null && note.isNotEmpty) 'pickup_note': note,
    }) as Map<String, dynamic>;
    return HomePickupBooking(
      pickupId: (json['pickup'] as Map<String, dynamic>)['pickup_id'] as String,
      relative: ReservationResult.fromJson(json['relative_booking'] as Map<String, dynamic>),
      passenger: ReservationResult.fromJson(json['passenger_booking'] as Map<String, dynamic>),
    );
  }

  /// The gateway is down: a screenshot of the payment, sent to the trip's
  /// Dispatcher in the chat, who confirms it.
  Future<void> sendPaymentScreenshot(String pickupId, Uint8List bytes, String filename) =>
      _api.upload('/home-pickups/$pickupId/proof', field: 'image', bytes: bytes, filename: filename);

  Future<PrivacyNotice> privacyNotice() async =>
      PrivacyNotice.fromJson(await _api.get('/trips/privacy-notice') as Map<String, dynamic>);

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

  /// Withdraw an accidental check-in. Allowed only while the booking is
  /// still `checked_in`; once scanned aboard there is nothing to retract.
  Future<Map<String, dynamic>> undoCheckIn(String bookingId) async {
    final json = await _api.delete('/bookings/$bookingId/check-in');
    return json as Map<String, dynamic>;
  }
}