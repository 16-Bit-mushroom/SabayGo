import 'dart:typed_data';

import '../../core/network/api_client.dart';
import 'trip_repository.dart';

/// A trip this crew member is rostered to.
///
/// Carries the route's stops so the passenger list and the walk-in form
/// know the sequence numbers without a second request at the van door.
class CrewTrip {
  const CrewTrip({
    required this.tripId,
    required this.routeName,
    required this.serviceDate,
    required this.departure,
    required this.status,
    required this.seatCapacity,
    required this.stops,
    this.tripLabel,
    this.plateNumber,
    this.operatorName,
    this.operatorLicence,
    this.paymentStatus = 'unpaid',
    this.crewAboard = false,
    this.rental,
  });

  final String tripId;
  final String? tripLabel;
  final String routeName;
  final DateTime serviceDate;
  final DateTime departure;
  final String status;
  final String? plateNumber;
  final int seatCapacity;
  final List<RouteStopDetail> stops;
  /// The operator, who drives: a name and licence beside the plate,
  /// never a user (brief 9).
  final String? operatorName;
  final String? operatorLicence;
  /// A2Z's share (brief 2.1): unpaid | paid | overridden | left_unpaid.
  final String paymentStatus;
  /// The Dispatcher rides as crew: not a boarding, not counted.
  final bool crewAboard;
  /// Set when this trip is a van rental (brief 2.5).
  final Rental? rental;

  bool get isScheduled => status == 'scheduled';
  bool get isCompleted => status == 'completed';
  bool get isBoarding => status == 'boarding';
  bool get isDeparted => status == 'departed' || status == 'completed';

  String get title => tripLabel ?? routeName;

  /// Where every passenger boards: the starting terminal (rev 603, brief
  /// 2.4). A reservation and a cash walk-in are judged against it.
  int get boardingStop => stops.isEmpty ? 1 : stops.first.stopSequence;

  String stopName(int sequence) {
    for (final s in stops) {
      if (s.stopSequence == sequence) return s.terminalName;
    }
    return 'Stop $sequence';
  }

  factory CrewTrip.fromJson(Map<String, dynamic> j) => CrewTrip(
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String?,
        routeName: j['route_name'] as String? ?? '',
        serviceDate: DateTime.parse(j['service_date'] as String),
        departure: DateTime.parse(j['departure_datetime'] as String),
        status: j['status'] as String,
        plateNumber: j['plate_number'] as String?,
        seatCapacity: j['seat_capacity'] as int? ?? 14,
        stops: (j['stops'] as List<dynamic>? ?? const [])
            .map((e) => RouteStopDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
        operatorName: j['operator_name'] as String?,
        operatorLicence: j['operator_licence'] as String?,
        paymentStatus: j['payment_status'] as String? ?? 'unpaid',
        crewAboard: j['crew_aboard'] as bool? ?? false,
        rental: j['rental'] == null ? null : Rental.fromJson(j['rental'] as Map<String, dynamic>),
      );

  CrewTrip copyWith({String? status}) => CrewTrip(
        tripId: tripId,
        tripLabel: tripLabel,
        routeName: routeName,
        serviceDate: serviceDate,
        departure: departure,
        status: status ?? this.status,
        plateNumber: plateNumber,
        seatCapacity: seatCapacity,
        stops: stops,
        operatorName: operatorName,
        operatorLicence: operatorLicence,
        paymentStatus: paymentStatus,
        crewAboard: crewAboard,
        rental: rental,
      );
}

/// The rental a special trip carries out: what the Dispatcher collects.
class Rental {
  const Rental({
    required this.requestId,
    required this.customerName,
    required this.customerContact,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.passengerCount,
    required this.fee,
    required this.paymentStatus,
  });

  final String requestId;
  final String? customerName;
  final String? customerContact;
  final String pickupAddress;
  final String destinationAddress;
  final int passengerCount;
  final double? fee;
  final String paymentStatus; // unpaid | paid

  factory Rental.fromJson(Map<String, dynamic> j) => Rental(
        requestId: j['request_id'] as String,
        customerName: j['customer_name'] as String?,
        customerContact: j['customer_contact'] as String?,
        pickupAddress: j['pickup_address'] as String,
        destinationAddress: j['destination_address'] as String,
        passengerCount: j['passenger_count'] as int,
        fee: j['rental_fee'] == null ? null : double.parse(j['rental_fee'].toString()),
        paymentStatus: j['payment_status'] as String,
      );
}

/// The camera's count aboard against the passenger list, before
/// departure (brief 2.4, 6.1).
class DoorCheck {
  const DoorCheck({
    required this.aboard,
    required this.listed,
    required this.explained,
    required this.excess,
    required this.crewAboard,
    required this.unlisted,
  });

  final int aboard;
  final int listed;
  final int explained;
  /// More aboard than listed, less those explained: blocks Depart.
  final int excess;
  final bool crewAboard;
  final List<UnlistedBoarding> unlisted;

  factory DoorCheck.fromJson(Map<String, dynamic> j) => DoorCheck(
        aboard: j['aboard'] as int,
        listed: j['listed'] as int,
        explained: j['explained'] as int,
        excess: j['excess'] as int,
        crewAboard: j['crew_aboard'] as bool,
        unlisted: [
          for (final u in j['unlisted'] as List) UnlistedBoarding.fromJson(u as Map<String, dynamic>)
        ],
      );
}

/// A boarding the phone counted that matched nobody on the passenger list.
class UnlistedBoarding {
  const UnlistedBoarding({required this.eventId, required this.at, required this.resolution, this.note});
  final String eventId;
  final DateTime at;
  final String resolution; // pending | listed | explained
  final String? note;

  bool get isPending => resolution == 'pending';

  factory UnlistedBoarding.fromJson(Map<String, dynamic> j) => UnlistedBoarding(
        eventId: j['event_id'] as String,
        at: DateTime.parse(j['event_at'] as String),
        resolution: j['resolution_status'] as String,
        note: j['resolution_note'] as String?,
      );
}

/// A2Z's share of the trip, line by line (brief 2.1-2.2): what the
/// Dispatcher hands to the Cashier.
class TripShare {
  const TripShare({
    required this.paymentStatus,
    required this.amountDue,
    required this.disputed,
    required this.lines,
  });

  final String paymentStatus;
  final double amountDue;
  final double disputed;
  final List<ShareLine> lines;

  factory TripShare.fromJson(Map<String, dynamic> j) => TripShare(
        paymentStatus: j['payment_status'] as String,
        amountDue: double.parse(j['amount_due'].toString()),
        disputed: double.parse(j['disputed'].toString()),
        lines: [for (final l in j['lines'] as List) ShareLine.fromJson(l as Map<String, dynamic>)],
      );
}

class ShareLine {
  const ShareLine({
    required this.lineId,
    required this.destination,
    required this.count,
    required this.fare,
    required this.share,
    required this.isTopUp,
  });

  final String lineId;
  final String destination;
  final int count;
  final double fare;
  final double share;
  final bool isTopUp;

  factory ShareLine.fromJson(Map<String, dynamic> j) => ShareLine(
        lineId: j['line_id'] as String,
        destination: (j['dest_terminal_name'] ?? 'No drop-off terminal') as String,
        count: j['passenger_count'] as int,
        fare: double.parse(j['fare_per_passenger'].toString()),
        share: double.parse(j['share_amount'].toString()),
        isTopUp: j['is_top_up'] as bool,
      );
}

/// A home pickup on the trip (brief 2.6, Table 41): the van stops at a
/// pin for a passenger a relative booked for.
class HomePickup {
  const HomePickup({
    required this.pickupId,
    required this.beneficiaryName,
    required this.beneficiaryContact,
    required this.latitude,
    required this.longitude,
    required this.note,
    required this.status,
    required this.arrivedAt,
    required this.hasPhoto,
  });

  final String pickupId;
  final String beneficiaryName;
  final String beneficiaryContact;
  final double latitude;
  final double longitude;
  final String? note;
  final String status; // pending | activated | arrived | boarded | no_show | cancelled
  final DateTime? arrivedAt;
  /// The relative sent a photo of a landmark at the pin. Not payment
  /// proof: nothing depends on it (brief 2.6).
  final bool hasPhoto;

  factory HomePickup.fromJson(Map<String, dynamic> j) => HomePickup(
        pickupId: j['pickup_id'] as String,
        beneficiaryName: j['beneficiary_name'] as String,
        beneficiaryContact: j['beneficiary_contact'] as String,
        latitude: double.parse(j['pickup_latitude'].toString()),
        longitude: double.parse(j['pickup_longitude'].toString()),
        note: j['pickup_note'] as String?,
        status: j['status'] as String,
        arrivedAt: j['arrived_at'] == null ? null : DateTime.parse(j['arrived_at'] as String),
        hasPhoto: j['photo_message_id'] != null,
      );
}

/// A driving flag on the trip (brief 6.4): for review, not proof.
class TripFlag {
  const TripFlag({
    required this.id,
    required this.type,
    required this.flagged,
    required this.start,
    required this.place,
    required this.reviewStatus,
    required this.disputeStatus,
  });

  final String id;
  final String type;
  final bool flagged;
  final DateTime start;
  final String? place;
  final String reviewStatus;
  final String? disputeStatus;

  String get kind => switch (type) {
        'overspeed' => 'Overspeed',
        'slow_stretch' => 'Slow stretch',
        'unscheduled_stop' => 'Unscheduled stop',
        _ => 'Stop on the way',
      };

  factory TripFlag.fromJson(Map<String, dynamic> j) => TripFlag(
        id: j['driving_event_id'] as String,
        type: j['flag_type'] as String,
        flagged: j['flagged'] as bool,
        start: DateTime.parse(j['start_at'] as String),
        place: j['place'] as String?,
        reviewStatus: j['review_status'] as String,
        disputeStatus: j['dispute_status'] as String?,
      );
}

/// An open 'Not a passenger trip' (Table 40).
class NonPassengerMove {
  const NonPassengerMove({required this.moveId, required this.reason, required this.startedAt});
  final String moveId;
  final String reason; // errand | fuel_or_repair | other
  final DateTime startedAt;

  factory NonPassengerMove.fromJson(Map<String, dynamic> j) => NonPassengerMove(
        moveId: j['move_id'] as String,
        reason: j['reason'] as String,
        startedAt: DateTime.parse(j['started_at'] as String),
      );
}

class ManifestPassenger {
  const ManifestPassenger({
    required this.bookingId,
    required this.bookingCode,
    required this.boardingStop,
    required this.alightingStop,
    required this.bookingType,
    required this.status,
    required this.paymentStatus,
    required this.fare,
    this.name,
  });

  final String bookingId;
  final String bookingCode;
  final int boardingStop;
  final int alightingStop;
  final String bookingType;
  final String status;
  final String paymentStatus;
  final double fare;
  final String? name;

  bool get isWalkIn => bookingType == 'walk_in';
  bool get isBoarded => status == 'boarded';
  bool get isCheckedIn => status == 'checked_in';
  bool get isUnpaid => paymentStatus == 'unpaid';
  bool get isNoShow => status == 'no_show';
  bool get isCancelled => status == 'cancelled';

  /// True only for a synthetic row built from the offline queue: a
  /// walk-in the Dispatcher logged in a dead zone that has not reached
  /// the server yet, so it has no real booking id or booking code.
  bool get isPendingSync => bookingId.isEmpty;

  /// A placeholder row for a walk-in still sitting in the offline queue.
  /// Never shown as a real booking -- `isPendingSync` distinguishes it
  /// from anything the server has actually recorded.
  factory ManifestPassenger.pendingSync({
    required int boardingStop,
    required int alightingStop,
    String? name,
  }) =>
      ManifestPassenger(
        bookingId: '',
        bookingCode: 'PENDING SYNC',
        boardingStop: boardingStop,
        alightingStop: alightingStop,
        bookingType: 'walk_in',
        status: 'pending_sync',
        paymentStatus: 'paid',
        fare: 0,
        name: name,
      );

  factory ManifestPassenger.fromJson(Map<String, dynamic> j) => ManifestPassenger(
        bookingId: j['booking_id'] as String,
        bookingCode: j['booking_code'] as String,
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        bookingType: j['booking_type'] as String? ?? 'app',
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String? ?? 'unpaid',
        fare: double.parse(j['fare_amount'].toString()),
        name: j['name'] as String?,
      );
}

class Manifest {
  const Manifest({
    required this.tripId,
    required this.departure,
    required this.status,
    required this.seatCapacity,
    required this.totalBookings,
    required this.boarded,
    required this.checkedIn,
    required this.awaiting,
    required this.unpaid,
    required this.passengers,
    this.tripLabel,
  });

  final String tripId;
  final String? tripLabel;
  final DateTime departure;
  final String status;
  final int seatCapacity;
  final int totalBookings;
  final int boarded;
  final int checkedIn;
  final int awaiting;
  final int unpaid;
  final List<ManifestPassenger> passengers;

  factory Manifest.fromJson(Map<String, dynamic> j) => Manifest(
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String?,
        departure: DateTime.parse(j['departure_datetime'] as String),
        status: j['status'] as String,
        seatCapacity: j['seat_capacity'] as int? ?? 14,
        totalBookings: j['total_bookings'] as int? ?? 0,
        boarded: j['boarded'] as int? ?? 0,
        checkedIn: j['checked_in'] as int? ?? 0,
        awaiting: j['awaiting'] as int? ?? 0,
        unpaid: j['unpaid'] as int? ?? 0,
        passengers: (j['passengers'] as List<dynamic>? ?? const [])
            .map((e) => ManifestPassenger.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A reservation or walk-up on the trip, as the Dispatcher finds it by
/// name or booking code (brief rev 721, 2.1). Unpaid ones come first: those
/// are the ones with cash still to collect.
class SeatOnList {
  const SeatOnList({
    required this.bookingId,
    required this.bookingCode,
    required this.passengerName,
    required this.contactNumber,
    required this.alightingStop,
    required this.fare,
    required this.bookingType,
    required this.status,
    required this.paymentStatus,
    required this.isHomePickupSeat,
    required this.paidAt,
  });

  final String bookingId;
  final String bookingCode;
  final String? passengerName;
  final String? contactNumber;
  final int alightingStop;
  final double fare;
  final String bookingType;
  final String status;
  final String paymentStatus;
  final bool isHomePickupSeat;
  final DateTime? paidAt;

  bool get isPaid => paymentStatus == 'paid';
  bool get isWalkIn => bookingType == 'walk_in';

  factory SeatOnList.fromJson(Map<String, dynamic> j) => SeatOnList(
        bookingId: j['booking_id'] as String,
        bookingCode: j['booking_code'] as String,
        passengerName: j['passenger_name'] as String?,
        contactNumber: j['contact_number'] as String?,
        alightingStop: j['alighting_stop'] as int,
        fare: double.parse(j['fare_amount'].toString()),
        bookingType: j['booking_type'] as String? ?? 'app',
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String,
        isHomePickupSeat: j['is_home_pickup_seat'] as bool? ?? false,
        paidAt: j['paid_at'] == null ? null : DateTime.parse(j['paid_at'] as String),
      );
}

/// What a Mark as Paid came back with. `restored` and `seatGone` are only
/// set on a mark that synced after the cutoff job released the seat: the
/// seat was given back, or there was none left and the Terminal Manager
/// has been alerted to settle the cash.
class MarkPaidResult {
  const MarkPaidResult({required this.seat, required this.restored, required this.seatGone, this.pickupNote});

  final SeatOnList seat;
  final bool restored;
  final bool seatGone;
  final String? pickupNote;

  factory MarkPaidResult.fromJson(Map<String, dynamic> j) => MarkPaidResult(
        seat: SeatOnList.fromJson(j),
        restored: j['restored'] as bool? ?? false,
        seatGone: j['seat_gone'] as bool? ?? false,
        pickupNote: j['pickup_note'] as String?,
      );

  /// What to tell the Dispatcher, or null when it is a plain Paid mark.
  String? get notice {
    final who = seat.passengerName ?? seat.bookingCode;
    if (seatGone) {
      return '$who paid after the seat was released and the trip is full. The Terminal Manager has been '
          'told; settle the fare with them.';
    }
    if (restored) return '$who paid after the cutoff; the seat has been given back.';
    return pickupNote;
  }
}

class WalkInResult {
  const WalkInResult({
    required this.bookingId,
    required this.bookingCode,
    required this.fare,
  });

  final String bookingId;
  final String bookingCode;
  final double fare;

  factory WalkInResult.fromJson(Map<String, dynamic> j) => WalkInResult(
        bookingId: j['booking_id'] as String,
        bookingCode: j['booking_code'] as String,
        fare: double.parse(j['fare_amount'].toString()),
      );
}

/// Everything crew do at the van: take reservations' cash, log walk-ups,
/// count heads, depart and arrive.
class OperationsRepository {
  OperationsRepository(this._api);
  final ApiClient _api;

  Future<List<CrewTrip>> assignedTrips() async {
    final json = await _api.get('/trips/assigned') as List<dynamic>;
    return json.map((e) => CrewTrip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Manifest> manifest(String tripId) async {
    final json = await _api.get('/trips/$tripId/manifest');
    return Manifest.fromJson(json as Map<String, dynamic>);
  }

  /// Approved fare per (boarding, alighting) stop pair on this trip's
  /// route. A preview for the walk-in screen only: the server computes the
  /// fare it actually charges. `fare_amount` is a Decimal, which arrives as
  /// a string, so it is parsed from either form.
  Future<Map<(int, int), double>> fares(String tripId) async {
    final json = await _api.get('/trips/$tripId/fares') as List<dynamic>;
    return {
      for (final e in json.cast<Map<String, dynamic>>())
        (e['from_stop_sequence'] as int, e['to_stop_sequence'] as int):
            double.parse(e['fare_amount'].toString()),
    };
  }

  /// Validate a ticket at the door. The server answers 200 for every
  /// outcome; read `accepted`.
  /// The trip's reservations and walk-ups, narrowed by name or booking
  /// code when [query] is given. Cancelled seats are not on it.
  Future<List<SeatOnList>> seats(String tripId, {String? query}) async {
    final json = await _api.get('/bookings/trip/$tripId/seats',
        query: {if (query != null && query.trim().isNotEmpty) 'q': query.trim()}) as List<dynamic>;
    return [for (final s in json) SeatOnList.fromJson(s as Map<String, dynamic>)];
  }

  /// The passenger handed over the fare in cash. [paidAt] is when the
  /// device recorded it, so a mark queued offline keeps its time. Safe to
  /// repeat: an already-paid seat is accepted and unchanged.
  Future<MarkPaidResult> markPaid(String bookingId, {required DateTime paidAt}) async {
    final json = await _api.post('/bookings/$bookingId/mark-paid',
        body: {'paid_at': paidAt.toIso8601String()});
    return MarkPaidResult.fromJson(json as Map<String, dynamic>);
  }

  /// Cancel a seat: the passenger asked (hand back any cash taken), or an
  /// unpaid reservation nobody came for. Returns the server's message.
  Future<String> dispatcherCancel(String bookingId, {required String reason}) async {
    final json = await _api.post('/bookings/$bookingId/dispatcher-cancel', body: {'reason': reason})
        as Map<String, dynamic>;
    return json['message'] as String? ?? 'Reservation cancelled.';
  }

  /// Record a cash passenger boarding at a terminal stop. The server
  /// prices it from the approved fare table.
  Future<WalkInResult> walkIn({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
    String? name,
    String? phone,
    bool wantsReceipt = false,
    // Set only by the offline sync queue, for a row a pre-rev-468 build
    // queued as a roadside pickup: sent so the server refuses it and it
    // stays visible, rather than being re-recorded as a terminal walk-in.
    bool queuedAsRoadside = false,
    // Set only by the offline sync queue, so a retry after a lost
    // response is recognised as a replay rather than a second booking.
    String? clientRequestId,
    // The unlisted boarding this person is (brief 2.4: fix the list).
    String? forEventId,
  }) async {
    final json = await _api.post('/bookings/walk-in', body: {
      'trip_id': tripId,
      'boarding_stop': boardingStop,
      'alighting_stop': alightingStop,
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'wants_receipt': wantsReceipt,
      if (queuedAsRoadside) 'is_roadside_pickup': true,
      'client_request_id': ?clientRequestId,
      'for_event_id': ?forEventId,
    });
    return WalkInResult.fromJson(json as Map<String, dynamic>);
  }

  /// The van has arrived and everyone is off: the trip is completed.
  /// Starting is the office's (rev 468, brief 4.2); the Dispatcher marks
  /// reservations Paid and lists walk-ups from the moment they are assigned.
  Future<void> arrive(String tripId) => _api.post('/trips/$tripId/arrive');

  // ---------------------------------------------- the dashboard (rev 603)
  Future<DoorCheck> doorCheck(String tripId) async =>
      DoorCheck.fromJson(await _api.get('/trips/$tripId/door-check') as Map<String, dynamic>);

  /// A reason for a boarding not on the list, kept with who and when.
  Future<void> explain(String eventId, String note) =>
      _api.post('/door-events/$eventId/explain', body: {'note': note});

  /// The Dispatcher rides as crew: logged, not counted toward the 14.
  Future<void> setCrew(String tripId, bool aboard) =>
      _api.put('/trips/$tripId/crew', body: {'aboard': aboard});

  /// Refused while more are aboard than listed and not explained.
  Future<void> depart(String tripId) => _api.post('/trips/$tripId/depart');

  Future<TripShare> share(String tripId) async =>
      TripShare.fromJson(await _api.get('/trips/$tripId/share') as Map<String, dynamic>);

  Future<List<HomePickup>> homePickups(String tripId) async => [
        for (final p in await _api.get('/home-pickups', query: {'trip_id': tripId}) as List)
          HomePickup.fromJson(p as Map<String, dynamic>)
      ];

  Future<void> activatePickup(String id) => _api.post('/home-pickups/$id/activate');
  Future<void> arrivedAtPickup(String id) => _api.post('/home-pickups/$id/arrived');
  Future<void> closePickup(String id, {required bool boarded}) =>
      _api.post('/home-pickups/$id/close', body: {'outcome': boarded ? 'boarded' : 'no_show'});
  /// The landmark photo the relative sent, to help find the pin.
  Future<Uint8List> pickupPhoto(String id) => _api.getBytes('/home-pickups/$id/photo');

  /// The rental fee collected in cash (brief 2.5).
  Future<void> rentalCash(String requestId) => _api.post('/special-trips/$requestId/cash');

  Future<List<TripFlag>> flags(String tripId) async => [
        for (final f in await _api.get('/driving-flags', query: {'trip_id': tripId}) as List)
          TripFlag.fromJson(f as Map<String, dynamic>)
      ];

  /// The open fare-line disputes of the trip, by line.
  Future<Set<String>> disputedLines(String tripId) async => {
        for (final d in await _api.get('/disputes', query: {'trip_id': tripId, 'status': 'open'}) as List)
          if ((d as Map<String, dynamic>)['line_id'] != null) d['line_id'] as String
      };

  /// The operator's dispute, recorded by the trip's Dispatcher.
  Future<void> dispute({String? lineId, String? flagId, required String statement}) =>
      _api.post('/disputes', body: {
        'subject': lineId != null ? 'fare_line' : 'driving_flag',
        'line_id': ?lineId,
        'driving_event_id': ?flagId,
        'operator_statement': statement,
      });

  Future<NonPassengerMove?> openMove() async {
    final json = await _api.get('/non-passenger-moves/open');
    return json == null ? null : NonPassengerMove.fromJson(json as Map<String, dynamic>);
  }

  Future<void> startMove(String reason, {String? note}) => _api.post('/non-passenger-moves',
      body: {'reason': reason, if (note != null && note.isNotEmpty) 'note': note});

  Future<void> endMove(String moveId) => _api.post('/non-passenger-moves/$moveId/end');

}
