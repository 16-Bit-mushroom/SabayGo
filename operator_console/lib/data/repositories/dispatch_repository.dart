import '../../core/network/api_client.dart';

class RouteSummary {
  const RouteSummary({
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.isActive,
    required this.stopCount,
  });

  final String routeId;
  final String routeCode;
  final String routeName;
  final bool isActive;
  final int stopCount;

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
        routeId: json['route_id'] as String,
        routeCode: json['route_code'] as String,
        routeName: json['route_name'] as String,
        isActive: json['is_active'] as bool,
        stopCount: json['stop_count'] as int,
      );
}

/// One trip on the office's trip board (GET /config/trips): live status,
/// crew and passenger counts -- what each Dispatcher sees, all at once.
class TripBoardEntry {
  const TripBoardEntry({
    required this.tripId,
    required this.tripLabel,
    required this.routeName,
    required this.departureDatetime,
    required this.status,
    required this.departedAt,
    required this.vanId,
    required this.dispatcherId,
    required this.plateNumber,
    required this.operatorName,
    required this.dispatcherName,
    required this.assignedByName,
    required this.startOpensAt,
    required this.startMode,
    required this.startedByName,
    required this.startedAt,
    required this.startReviewStatus,
    required this.auditStatus,
    required this.unauditedReason,
    required this.departureSource,
    required this.changeNote,
    required this.paymentStatus,
    required this.seatCapacity,
    required this.booked,
    required this.checkedIn,
    required this.boarded,
    required this.noShow,
  });

  final String tripId;
  final String? tripLabel;
  final String routeName;
  final DateTime departureDatetime;
  final String status;
  final DateTime? departedAt;
  final String? vanId;
  final String? dispatcherId;
  final String? plateNumber;
  /// The van's owner, who drives it. A name beside the plate, never a user.
  final String? operatorName;
  final String? dispatcherName;

  // The lifecycle (rev 468, brief 4): assignment at the van's turn, the
  // start (by a person, or by the system and then held for review), the
  // phone's audit state, and the Terminal Manager's last change.
  final String? assignedByName;
  final DateTime startOpensAt;
  final String? startMode; // manual | auto_assigned | auto_detected
  final String? startedByName;
  final DateTime? startedAt;
  final String startReviewStatus; // not_required | pending | reviewed
  final String auditStatus; // audited | unaudited
  final String? unauditedReason;
  final String? departureSource; // confirmed | detected
  final String? changeNote;
  /// A2Z's 15 % (brief 2.1): unpaid | paid | overridden | left_unpaid.
  final String paymentStatus;

  bool get isAssigned => vanId != null && dispatcherId != null;
  bool get awaitsReview => startReviewStatus == 'pending';
  final int seatCapacity;
  final int booked;
  final int checkedIn;
  final int boarded;
  final int noShow;

  factory TripBoardEntry.fromJson(Map<String, dynamic> j) => TripBoardEntry(
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String?,
        routeName: j['route_name'] as String,
        departureDatetime: DateTime.parse(j['departure_datetime'] as String),
        status: j['status'] as String,
        departedAt: j['departed_at'] == null ? null : DateTime.parse(j['departed_at'] as String),
        vanId: j['van_id'] as String?,
        dispatcherId: j['dispatcher_id'] as String?,
        plateNumber: j['plate_number'] as String?,
        operatorName: j['operator_name'] as String?,
        dispatcherName: j['dispatcher_name'] as String?,
        assignedByName: j['assigned_by_name'] as String?,
        startOpensAt: DateTime.parse(j['start_opens_at'] as String),
        startMode: j['start_mode'] as String?,
        startedByName: j['started_by_name'] as String?,
        startedAt: j['started_at'] == null ? null : DateTime.parse(j['started_at'] as String),
        startReviewStatus: j['start_review_status'] as String,
        auditStatus: j['audit_status'] as String,
        unauditedReason: j['unaudited_reason'] as String?,
        departureSource: j['departure_source'] as String?,
        changeNote: j['change_note'] as String?,
        paymentStatus: j['payment_status'] as String,
        seatCapacity: j['seat_capacity'] as int,
        booked: j['booked'] as int,
        checkedIn: j['checked_in'] as int,
        boarded: j['boarded'] as int,
        noShow: j['no_show'] as int,
      );
}

/// The Dispatcher's manifest (GET /trips/{id}/manifest), read by the office.
/// Same endpoint, same fields, so the two screens cannot disagree.
class TripManifest {
  const TripManifest({
    required this.status,
    required this.boarded,
    required this.checkedIn,
    required this.awaiting,
    required this.unpaid,
    required this.passengers,
  });

  final String status;
  final int boarded;
  final int checkedIn;
  final int awaiting;
  final int unpaid;
  final List<ManifestPassenger> passengers;

  factory TripManifest.fromJson(Map<String, dynamic> j) => TripManifest(
        status: j['status'] as String,
        boarded: j['boarded'] as int,
        checkedIn: j['checked_in'] as int,
        awaiting: j['awaiting'] as int,
        unpaid: j['unpaid'] as int,
        passengers: (j['passengers'] as List)
            .map((e) => ManifestPassenger.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ManifestPassenger {
  const ManifestPassenger({
    required this.ticketNumber,
    required this.name,
    required this.boardingStop,
    required this.alightingStop,
    required this.bookingType,
    required this.status,
    required this.fareAmount,
  });

  final String ticketNumber;
  final String? name;
  final int boardingStop;
  final int alightingStop;
  final String bookingType;
  final String status;
  final String fareAmount;

  factory ManifestPassenger.fromJson(Map<String, dynamic> j) => ManifestPassenger(
        ticketNumber: j['ticket_number'] as String,
        name: j['name'] as String?,
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        bookingType: j['booking_type'] as String,
        status: j['status'] as String,
        fareAmount: j['fare_amount'].toString(),
      );
}

class TripStop {
  const TripStop({required this.sequence, required this.name});
  final int sequence;
  final String name;

  factory TripStop.fromJson(Map<String, dynamic> j) => TripStop(
        sequence: j['stop_sequence'] as int,
        name: j['terminal_name'] as String,
      );
}

class DispatchRepository {
  DispatchRepository(this._api);
  final ApiClient _api;

  Future<List<RouteSummary>> listRoutes() async {
    final json = await _api.get('/config/routes');
    return (json as List)
        .map((e) => RouteSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Every trip on [day] with its live status. Defaults server-side to today.
  Future<List<TripBoardEntry>> tripBoard(DateTime day) async {
    final iso = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final json = await _api.get('/config/trips', query: {'date': iso});
    return (json as List)
        .map((e) => TripBoardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The trip's stops in order. Leg k runs from stop k to stop k+1.
  Future<List<TripStop>> tripStops(String tripId) async {
    final json = await _api.get('/trips/$tripId/stops');
    return (json as List)
        .map((e) => TripStop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TripManifest> manifest(String tripId) async {
    final json = await _api.get('/trips/$tripId/manifest');
    return TripManifest.fromJson(json as Map<String, dynamic>);
  }

  // ---------------------------------------------------------- lifecycle
  // The office assigns, starts and departs; the Terminal Manager alone
  // reviews an automatic start, changes a started trip's van or voids it.

  Future<void> assign(String tripId, {String? vanId, String? dispatcherId}) =>
      _api.put('/trips/$tripId/assignment', body: {
        'van_id': vanId,
        'dispatcher_id': dispatcherId,
      });

  /// Starts the trip. Returns the warnings for the person who started it:
  /// an expired licence, no phone with the van. A start is never refused
  /// for them.
  Future<List<String>> start(String tripId, {String? vanId}) async {
    final json = await _api.post('/trips/$tripId/start',
        body: {if (vanId != null) 'van_id': vanId});
    return ((json as Map<String, dynamic>)['warnings'] as List).cast<String>();
  }

  Future<void> depart(String tripId) => _api.post('/trips/$tripId/depart');

  Future<void> reviewStart(String tripId, {String? vanId, String? note}) =>
      _api.post('/trips/$tripId/start-review', body: {
        if (vanId != null) 'van_id': vanId,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<void> changeVan(String tripId, {required String vanId, required String reason}) =>
      _api.post('/trips/$tripId/change-van', body: {'van_id': vanId, 'reason': reason});

  Future<void> voidTrip(String tripId, {required String reason}) =>
      _api.post('/trips/$tripId/void', body: {'reason': reason});

  // ------------------------------------------------------- A2Z's share
  // The Cashier records the 15 % the Dispatcher hands over; Start waits
  // for it (brief 2.1). The Terminal Manager may lift the block, with a
  // reason, but records no payment.

  /// The share does not carry the trip's status; the board's is passed in.
  Future<TripShare> share(String tripId, {required String tripStatus}) async => TripShare.fromJson(
        await _api.get('/trips/$tripId/share') as Map<String, dynamic>,
        beforeDeparture: tripStatus == 'scheduled' || tripStatus == 'boarding',
      );

  /// Before departure the payment is the trip's; after, it goes on the
  /// van's statement, where a trip that left unpaid is still owed.
  Future<void> recordPayment(TripShare share, {required String amount, String? reference}) {
    final body = {'amount': amount, if (reference != null && reference.isNotEmpty) 'reference': reference};
    return share.beforeDeparture
        ? _api.post('/trips/${share.tripId}/payment', body: body)
        : _api.post('/statements/${share.remittanceId}/payments', body: body);
  }

  Future<void> overridePayment(String tripId, {required String note}) =>
      _api.post('/trips/$tripId/payment-override', body: {'note': note});
}

/// A trip's share (GET /trips/{id}/share). `amountDue` is the van's
/// undisputed balance for the day: this trip's share plus anything the van
/// still owes, which is what the Cashier should receive now.
class TripShare {
  const TripShare({
    required this.tripId,
    required this.paymentStatus,
    required this.remittanceId,
    required this.amountDue,
    required this.disputed,
    required this.lines,
    required this.beforeDeparture,
  });

  final String tripId;
  final String paymentStatus;
  final String? remittanceId;
  final double amountDue;
  final double disputed;
  final List<ShareLine> lines;
  final bool beforeDeparture;

  factory TripShare.fromJson(Map<String, dynamic> j, {required bool beforeDeparture}) => TripShare(
        tripId: j['trip_id'] as String,
        paymentStatus: j['payment_status'] as String,
        remittanceId: j['remittance_id'] as String?,
        amountDue: double.parse(j['amount_due'].toString()),
        disputed: double.parse(j['disputed'].toString()),
        lines: (j['lines'] as List).map((e) => ShareLine.fromJson(e as Map<String, dynamic>)).toList(),
        beforeDeparture: beforeDeparture,
      );
}

/// One fare line: passengers to one drop-off terminal at one fare.
class ShareLine {
  const ShareLine({
    required this.destination,
    required this.passengerCount,
    required this.farePerPassenger,
    required this.shareAmount,
    required this.isTopUp,
  });

  final String destination;
  final int passengerCount;
  final double farePerPassenger;
  final double shareAmount;
  final bool isTopUp;

  factory ShareLine.fromJson(Map<String, dynamic> j) => ShareLine(
        destination: (j['dest_terminal_name'] ?? 'No drop-off terminal') as String,
        passengerCount: j['passenger_count'] as int,
        farePerPassenger: double.parse(j['fare_per_passenger'].toString()),
        shareAmount: double.parse(j['share_amount'].toString()),
        isTopUp: j['is_top_up'] as bool,
      );
}
