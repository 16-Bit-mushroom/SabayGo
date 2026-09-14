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
