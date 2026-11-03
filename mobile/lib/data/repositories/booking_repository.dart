import 'dart:typed_data';

import '../../core/network/api_client.dart';

/// A reservation as the passenger sees it (brief rev 721).
///
/// No seat number: UV Express does not assign seats. The system counts
/// how much space is taken on each section of road so a van is never
/// oversold, but nobody is told where to sit.
///
/// Cash only: the passenger gives the booking code to the Dispatcher at
/// the terminal and pays there. The seat stays Unpaid until the Dispatcher
/// marks it Paid, and an unpaid one is released before departure.
class BookingSummary {
  const BookingSummary({
    required this.bookingId,
    required this.bookingCode,
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
    required this.paymentStatus,
    required this.canCancel,
    this.paidAt,
    this.cancelReason,
    this.payBy,
    this.boardingDueAt,
    this.checkinOpensAt,
    this.homePickup,
  });

  final String bookingId;
  /// The short code the passenger gives the Dispatcher.
  final String bookingCode;
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
  /// 'unpaid' until the Dispatcher takes the cash, then 'paid'.
  final String paymentStatus;
  final DateTime? paidAt;

  /// Only an unpaid seat, before the trip's list locks. The server checks
  /// again on the request; this only decides whether to offer it.
  final bool canCancel;

  /// Why it ended: 'auto_release' (unpaid at the cutoff), the passenger,
  /// or the Dispatcher.
  final String? cancelReason;

  /// When the seat is released if it is still unpaid: the passenger pays
  /// the Dispatcher before this. Null once paid or no longer standing.
  final DateTime? payBy;

  /// When the van is due at *this passenger's* boarding stop, and when
  /// check-in there opens. Computed server-side from the stop's offset
  /// on the route; a stop-3 passenger is not at the origin at departure.
  final DateTime? boardingDueAt;
  final DateTime? checkinOpensAt;

  /// Set when this is one of a home pickup's two seats (brief 2.6).
  final HomePickupRef? homePickup;

  bool get isPaid => paymentStatus == 'paid';
  bool get isConfirmed => status == 'confirmed';
  bool get isCheckedIn => status == 'checked_in';
  bool get isBoarded => status == 'boarded';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => isConfirmed || isCheckedIn || isBoarded;
  bool get wasReleased => cancelReason == 'auto_release';

  String get statusLabel => switch (status) {
        'confirmed' || 'checked_in' => isPaid ? 'Paid' : 'Unpaid',
        'boarded' => 'On board',
        'completed' => 'Completed',
        'cancelled' => wasReleased ? 'Released, unpaid' : 'Cancelled',
        // The server cannot tell who boarded once the van has left: every
        // seat still on the trip is closed at departure. A paid one may
        // well have ridden, so it is not called a missed trip.
        'no_show' => isPaid ? 'Trip departed' : 'Missed',
        _ => status,
      };

  /// Why a cancelled reservation ended, in the passenger's words.
  String? get cancelLabel => switch (cancelReason) {
        'auto_release' => 'Not paid at the terminal before the cutoff, so the space was released.',
        'passenger_asked_dispatcher' => 'Cancelled by the Dispatcher at your request.',
        'forgot_to_cancel' => 'Cancelled by the Dispatcher: nobody came for it.',
        null => null,
        _ => 'Cancelled.',
      };

  factory BookingSummary.fromJson(Map<String, dynamic> j) => BookingSummary(
        bookingId: j['booking_id'] as String,
        bookingCode: j['booking_code'] as String,
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
        paymentStatus: j['payment_status'] as String? ?? 'unpaid',
        paidAt: j['paid_at'] == null ? null : DateTime.parse(j['paid_at'] as String),
        canCancel: j['can_cancel'] as bool? ?? false,
        cancelReason: j['cancel_reason'] as String?,
        payBy: j['pay_by'] == null ? null : DateTime.parse(j['pay_by'] as String),
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
    required this.status,
    required this.photoSent,
  });

  final String pickupId;
  final String beneficiaryName;
  final bool isPassengerSeat;
  final String status;
  /// A photo of a landmark at the pickup place. Nothing depends on it.
  final bool photoSent;

  factory HomePickupRef.fromJson(Map<String, dynamic> j) => HomePickupRef(
        pickupId: j['pickup_id'] as String,
        beneficiaryName: j['beneficiary_name'] as String,
        isPassengerSeat: j['is_passenger_seat'] as bool,
        status: j['status'] as String,
        photoSent: j['photo_sent'] as bool? ?? false,
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

/// The result of claiming space: a reservation, Unpaid until the
/// Dispatcher takes the cash at the terminal.
class ReservationResult {
  const ReservationResult({
    required this.bookingId,
    required this.bookingCode,
    required this.fare,
    required this.status,
    required this.paymentStatus,
  });

  final String bookingId;
  final String bookingCode;
  final double fare;
  final String status;
  final String paymentStatus;

  factory ReservationResult.fromJson(Map<String, dynamic> j) =>
      ReservationResult(
        bookingId: j['booking_id'] as String,
        bookingCode: j['booking_code'] as String,
        fare: double.parse(j['fare_amount'].toString()),
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String? ?? 'unpaid',
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
  /// The reservation stays Unpaid until the Dispatcher marks it Paid at
  /// the terminal, and is released `unpaid_cutoff_min` before departure
  /// if nobody does.
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
  /// The reservation screen refreshes this to see the Paid mark arrive.
  Future<BookingSummary> byId(String bookingId) async {
    final json = await _api.get('/bookings/$bookingId');
    return BookingSummary.fromJson(json as Map<String, dynamic>);
  }

  /// Book for someone else (brief 2.6): the relative's seat and the
  /// passenger's, from the starting terminal to one drop-off, in one go.
  /// The relative pays both in cash to the Dispatcher at the terminal.
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

  /// A photo of a landmark at the pickup place, sent to the trip's
  /// Dispatcher in the chat to help find the gate. Not payment proof.
  Future<void> sendLandmarkPhoto(String pickupId, Uint8List bytes, String filename) =>
      _api.upload('/home-pickups/$pickupId/photo', field: 'image', bytes: bytes, filename: filename);

  Future<PrivacyNotice> privacyNotice() async =>
      PrivacyNotice.fromJson(await _api.get('/trips/privacy-notice') as Map<String, dynamic>);

  /// Cancel an unpaid reservation and free the space. A paid one is
  /// cancelled by the Dispatcher, who hands the cash back.
  Future<void> cancel(String bookingId) =>
      _api.post('/bookings/$bookingId/cancel');

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
  /// still `checked_in`.
  Future<Map<String, dynamic>> undoCheckIn(String bookingId) async {
    final json = await _api.delete('/bookings/$bookingId/check-in');
    return json as Map<String, dynamic>;
  }
}