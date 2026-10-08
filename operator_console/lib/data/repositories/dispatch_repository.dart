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

/// One row of the dispatch board -- a scheduled or special departure.
///
/// Sourced from the same reconciliation view the revenue module reads, so
/// a trip with zero bookings still appears: the view LEFT JOINs bookings
/// rather than requiring one.
class TripBoardRow {
  const TripBoardRow({
    required this.tripId,
    required this.serviceDate,
    required this.departureDatetime,
    required this.routeName,
    this.plateNumber,
    required this.seatCapacity,
    required this.totalBookings,
    required this.pendingAudits,
  });

  final String tripId;
  final DateTime serviceDate;
  final DateTime departureDatetime;
  final String routeName;
  final String? plateNumber;
  final int seatCapacity;
  final int totalBookings;
  final int pendingAudits;

  bool get hasDeparted => departureDatetime.isBefore(DateTime.now());

  factory TripBoardRow.fromJson(Map<String, dynamic> json) => TripBoardRow(
        tripId: json['trip_id'] as String,
        serviceDate: DateTime.parse(json['service_date'] as String),
        departureDatetime: DateTime.parse(json['departure_datetime'] as String),
        routeName: json['route_name'] as String,
        plateNumber: json['plate_number'] as String?,
        seatCapacity: json['seat_capacity'] as int,
        totalBookings: json['total_bookings'] as int,
        pendingAudits: json['pending_audits'] as int,
      );
}

/// One trip on the office's trip board (GET /config/trips): live status,
/// crew and passenger counts -- what each conductor sees, all at once.
class TripBoardEntry {
  const TripBoardEntry({
    required this.tripId,
    required this.tripLabel,
    required this.routeName,
    required this.departureDatetime,
    required this.status,
    required this.departedAt,
    required this.plateNumber,
    required this.driverName,
    required this.conductorName,
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
  final String? plateNumber;
  final String? driverName;
  final String? conductorName;
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
        plateNumber: j['plate_number'] as String?,
        driverName: j['driver_name'] as String?,
        conductorName: j['conductor_name'] as String?,
        seatCapacity: j['seat_capacity'] as int,
        booked: j['booked'] as int,
        checkedIn: j['checked_in'] as int,
        boarded: j['boarded'] as int,
        noShow: j['no_show'] as int,
      );
}

/// The conductor's manifest (GET /trips/{id}/manifest), read by the office.
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
    required this.isRoadsidePickup,
    required this.pickupLandmark,
  });

  final String ticketNumber;
  final String? name;
  final int boardingStop;
  final int alightingStop;
  final String bookingType;
  final String status;
  final String fareAmount;
  final bool isRoadsidePickup;
  final String? pickupLandmark;

  factory ManifestPassenger.fromJson(Map<String, dynamic> j) => ManifestPassenger(
        ticketNumber: j['ticket_number'] as String,
        name: j['name'] as String?,
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        bookingType: j['booking_type'] as String,
        status: j['status'] as String,
        fareAmount: j['fare_amount'].toString(),
        isRoadsidePickup: j['is_roadside_pickup'] as bool? ?? false,
        pickupLandmark: j['pickup_landmark'] as String?,
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

  /// Today's departures, generated or special, newest scheduled first.
  Future<List<TripBoardRow>> todaysTrips() async {
    final today = DateTime.now();
    final iso = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final json = await _api.get('/revenue/trips', query: {
      'date_from': iso,
      'date_to': iso,
      'limit': 200,
    });
    return (json as List)
        .map((e) => TripBoardRow.fromJson(e as Map<String, dynamic>))
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

  /// An ad-hoc departure outside the regular schedule template.
  Future<Map<String, dynamic>> createSpecialTrip({
    required String routeId,
    required DateTime departureDatetime,
    String? vanId,
    String? driverId,
    String? conductorId,
    String? tripLabel,
  }) async {
    final json = await _api.post('/config/trips/special', body: {
      'route_id': routeId,
      'departure_datetime': departureDatetime.toIso8601String(),
      if (vanId != null) 'van_id': vanId,
      if (driverId != null) 'driver_id': driverId,
      if (conductorId != null) 'conductor_id': conductorId,
      if (tripLabel != null && tripLabel.isNotEmpty) 'trip_label': tripLabel,
    });
    return json as Map<String, dynamic>;
  }
}
