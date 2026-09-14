import '../../core/network/api_client.dart';
import 'trip_repository.dart';

/// A trip this crew member is rostered to.
///
/// Carries the route's stops so the scanner and the walk-in form know
/// the sequence numbers without a second request at the van door.
class CrewTrip {
  const CrewTrip({
    required this.tripId,
    required this.routeName,
    required this.serviceDate,
    required this.departure,
    required this.status,
    required this.seatCapacity,
    required this.roleOnTrip,
    required this.stops,
    this.tripLabel,
    this.plateNumber,
  });

  final String tripId;
  final String? tripLabel;
  final String routeName;
  final DateTime serviceDate;
  final DateTime departure;
  final String status;
  final String? plateNumber;
  final int seatCapacity;
  final String roleOnTrip;
  final List<RouteStopDetail> stops;

  bool get isScheduled => status == 'scheduled';
  bool get isBoarding => status == 'boarding';
  bool get isDeparted => status == 'departed' || status == 'completed';

  String get title => tripLabel ?? routeName;

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
        roleOnTrip: j['role_on_trip'] as String? ?? 'conductor',
        stops: (j['stops'] as List<dynamic>? ?? const [])
            .map((e) => RouteStopDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
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
        roleOnTrip: roleOnTrip,
        stops: stops,
      );
}

class ManifestPassenger {
  const ManifestPassenger({
    required this.bookingId,
    required this.ticketNumber,
    required this.boardingStop,
    required this.alightingStop,
    required this.bookingType,
    required this.status,
    required this.fare,
    required this.fareIsManual,
    required this.isRoadsidePickup,
    this.pickupLandmark,
    this.name,
  });

  final String bookingId;
  final String ticketNumber;
  final int boardingStop;
  final int alightingStop;
  final String bookingType;
  final String status;
  final double fare;
  final bool fareIsManual;
  final bool isRoadsidePickup;
  final String? pickupLandmark;
  final String? name;

  bool get isWalkIn => bookingType == 'walk_in';
  bool get isBoarded => status == 'boarded';
  bool get isCheckedIn => status == 'checked_in';
  bool get isUnpaid => status == 'pending';
  bool get isNoShow => status == 'no_show';
  bool get isCancelled => status == 'cancelled';

  factory ManifestPassenger.fromJson(Map<String, dynamic> j) => ManifestPassenger(
        bookingId: j['booking_id'] as String,
        ticketNumber: j['ticket_number'] as String,
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        bookingType: j['booking_type'] as String? ?? 'app',
        status: j['status'] as String,
        fare: double.parse(j['fare_amount'].toString()),
        fareIsManual: j['fare_is_manual'] as bool? ?? false,
        isRoadsidePickup: j['is_roadside_pickup'] as bool? ?? false,
        pickupLandmark: j['pickup_landmark'] as String?,
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

/// The verdict on a scanned QR. Always returned, never thrown: a
/// refused ticket is a normal outcome at a van door, not an error.
class ScanVerdict {
  const ScanVerdict({
    required this.result,
    required this.accepted,
    required this.message,
    this.ticketNumber,
    this.boardingStop,
    this.alightingStop,
  });

  final String result;
  final bool accepted;
  final String message;
  final String? ticketNumber;
  final int? boardingStop;
  final int? alightingStop;

  factory ScanVerdict.fromJson(Map<String, dynamic> j) => ScanVerdict(
        result: j['result'] as String,
        accepted: j['accepted'] as bool,
        message: j['message'] as String,
        ticketNumber: j['ticket_number'] as String?,
        boardingStop: j['boarding_stop'] as int?,
        alightingStop: j['alighting_stop'] as int?,
      );
}

class WalkInResult {
  const WalkInResult({
    required this.bookingId,
    required this.ticketNumber,
    required this.fare,
    required this.fareIsManual,
  });

  final String bookingId;
  final String ticketNumber;
  final double fare;
  final bool fareIsManual;

  factory WalkInResult.fromJson(Map<String, dynamic> j) => WalkInResult(
        bookingId: j['booking_id'] as String,
        ticketNumber: j['ticket_number'] as String,
        fare: double.parse(j['fare_amount'].toString()),
        fareIsManual: j['fare_is_manual'] as bool? ?? false,
      );
}

class HeadcountResult {
  const HeadcountResult({
    required this.confirmedCount,
    required this.manifestCount,
    required this.variance,
    required this.message,
  });

  final int confirmedCount;
  final int manifestCount;
  final int variance;
  final String message;

  factory HeadcountResult.fromJson(Map<String, dynamic> j) => HeadcountResult(
        confirmedCount: j['confirmed_count'] as int,
        manifestCount: j['manifest_count'] as int,
        variance: j['variance'] as int,
        message: j['message'] as String,
      );
}

class Remittance {
  const Remittance({
    required this.tripId,
    required this.bookingCount,
    required this.expectedAmount,
    required this.status,
    this.remittanceId,
    this.declaredAmount,
    this.receivedAmount,
    this.variance,
    this.submittedAt,
    this.notes,
  });

  final String? remittanceId;
  final String tripId;
  final int bookingCount;
  final double expectedAmount;
  final double? declaredAmount;
  final double? receivedAmount;
  final double? variance;
  final String status;
  final DateTime? submittedAt;
  final String? notes;

  /// A preview has no id; only a submitted handover is a record.
  bool get isSubmitted => remittanceId != null;

  factory Remittance.fromJson(Map<String, dynamic> j) => Remittance(
        remittanceId: j['remittance_id'] as String?,
        tripId: j['trip_id'] as String,
        bookingCount: j['booking_count'] as int? ?? 0,
        expectedAmount: double.parse(j['expected_amount'].toString()),
        declaredAmount: j['declared_amount'] == null
            ? null
            : double.parse(j['declared_amount'].toString()),
        receivedAmount: j['received_amount'] == null
            ? null
            : double.parse(j['received_amount'].toString()),
        variance: j['variance'] == null ? null : double.parse(j['variance'].toString()),
        status: j['status'] as String,
        submittedAt: j['submitted_at'] == null
            ? null
            : DateTime.parse(j['submitted_at'] as String),
        notes: j['notes'] as String?,
      );
}

/// Everything crew do at the van: scan, log cash passengers, count
/// heads, open and close boarding, hand over cash.
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

  /// Validate a ticket at the door. The server answers 200 for every
  /// outcome; read `accepted`.
  Future<ScanVerdict> scan({
    required String qrPayload,
    required String tripId,
    required int stopSequence,
  }) async {
    final json = await _api.post('/scans', body: {
      'qr_payload': qrPayload,
      'trip_id': tripId,
      'stop_sequence': stopSequence,
    });
    return ScanVerdict.fromJson(json as Map<String, dynamic>);
  }

  /// Record a cash passenger.
  ///
  /// A roadside pickup is anchored to the last terminal passed, with the
  /// conductor setting the fare — they have not travelled a fare-table
  /// distance, so the matrix has no answer for them.
  Future<WalkInResult> walkIn({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
    String? name,
    String? phone,
    bool wantsReceipt = false,
    bool isRoadsidePickup = false,
    String? pickupLandmark,
    double? fareOverride,
    String? fareNote,
  }) async {
    final json = await _api.post('/bookings/walk-in', body: {
      'trip_id': tripId,
      'boarding_stop': boardingStop,
      'alighting_stop': alightingStop,
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'wants_receipt': wantsReceipt,
      'is_roadside_pickup': isRoadsidePickup,
      if (pickupLandmark != null && pickupLandmark.isNotEmpty)
        'pickup_landmark': pickupLandmark,
      if (fareOverride != null) 'fare_override': fareOverride.toStringAsFixed(2),
      if (fareNote != null && fareNote.isNotEmpty) 'fare_note': fareNote,
    });
    return WalkInResult.fromJson(json as Map<String, dynamic>);
  }

  Future<HeadcountResult> headcount({
    required String tripId,
    required int stopSequence,
    required int confirmedCount,
  }) async {
    final json = await _api.post('/trips/$tripId/headcount', body: {
      'stop_sequence': stopSequence,
      'confirmed_count': confirmedCount,
    });
    return HeadcountResult.fromJson(json as Map<String, dynamic>);
  }

  Future<void> startBoarding(String tripId) =>
      _api.post('/trips/$tripId/start-boarding');

  /// Close boarding. Confirmed passengers who never scanned become
  /// no-shows and their space is released.
  Future<void> depart(String tripId) => _api.post('/trips/$tripId/depart');

  /// The cash this crew member is holding for a trip, computed by the
  /// server from the bookings they logged — never typed in.
  Future<Remittance> remittancePreview(String tripId) async {
    final json = await _api.get('/remittances/trips/$tripId/preview');
    return Remittance.fromJson(json as Map<String, dynamic>);
  }

  Future<Remittance> submitRemittance({
    required String tripId,
    required double declaredAmount,
    String? notes,
  }) async {
    final json = await _api.post('/remittances/trips/$tripId/submit', body: {
      'declared_amount': declaredAmount.toStringAsFixed(2),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return Remittance.fromJson(json as Map<String, dynamic>);
  }
}
