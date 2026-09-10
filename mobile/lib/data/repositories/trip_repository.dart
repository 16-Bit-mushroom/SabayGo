import '../../core/network/api_client.dart';

/// A terminal at a position on a route.
///
/// `stopSequence` is the position, not an identity — the same terminal
/// can be stop 2 on one route and stop 5 on another. Booking works in
/// stop sequences because that is what the fare matrix and the seat
/// inventory are keyed on.
class TerminalStop {
  const TerminalStop({
    required this.terminalId,
    required this.terminalName,
    required this.city,
    required this.stopSequence,
  });

  final String terminalId;
  final String terminalName;
  final String city;
  final int stopSequence;

  factory TerminalStop.fromJson(Map<String, dynamic> j) => TerminalStop(
        terminalId: j['terminal_id'] as String,
        terminalName: j['terminal_name'] as String,
        city: j['city'] as String,
        stopSequence: j['stop_sequence'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is TerminalStop && other.terminalId == terminalId;

  @override
  int get hashCode => terminalId.hashCode;
}

/// One bookable departure for a specific journey.
///
/// Fare and availability are properties of the *segment*, not the trip:
/// Ecoland→Digos and Ecoland→Cotabato on the same van have different
/// prices and can have different space. That is why the search requires
/// both stops.
class TripSummary {
  const TripSummary({
    required this.tripId,
    required this.routeName,
    required this.departure,
    required this.boardingStop,
    required this.alightingStop,
    required this.boardingTerminal,
    required this.alightingTerminal,
    required this.fare,
    required this.spacesAvailable,
    required this.isSpecialTrip,
    this.tripLabel,
    this.plateNumber,
  });

  final String tripId;
  final String routeName;
  final String? tripLabel;
  final DateTime departure;
  final int boardingStop;
  final int alightingStop;
  final String boardingTerminal;
  final String alightingTerminal;
  final double fare;
  final int spacesAvailable;
  final String? plateNumber;
  final bool isSpecialTrip;

  bool get isFull => spacesAvailable <= 0;
  bool get hasDeparted => departure.isBefore(DateTime.now());

  /// Space is scarce enough to be worth flagging in the UI. Chosen so a
  /// passenger sees the warning while there is still time to act.
  bool get isNearlyFull => spacesAvailable > 0 && spacesAvailable <= 3;

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        tripId: j['trip_id'] as String,
        routeName: j['route_name'] as String? ?? '',
        tripLabel: j['trip_label'] as String?,
        departure: DateTime.parse(j['departure_datetime'] as String),
        boardingStop: j['boarding_stop'] as int,
        alightingStop: j['alighting_stop'] as int,
        boardingTerminal: j['boarding_terminal'] as String? ?? '',
        alightingTerminal: j['alighting_terminal'] as String? ?? '',
        // Money crosses the wire as a decimal string so it is not
        // rounded by JSON's double. Parsed once, here.
        fare: double.parse(j['fare_amount'].toString()),
        spacesAvailable: j['seats_available'] as int? ?? 0,
        plateNumber: j['plate_number'] as String?,
        isSpecialTrip: j['is_special_trip'] as bool? ?? false,
      );
}

/// A stop on a route, with its scheduled offset from the origin.
class RouteStopDetail {
  const RouteStopDetail({
    required this.stopSequence,
    required this.terminalId,
    required this.terminalName,
    required this.city,
    required this.offsetMinutes,
  });

  final int stopSequence;
  final String terminalId;
  final String terminalName;
  final String city;
  final int offsetMinutes;

  factory RouteStopDetail.fromJson(Map<String, dynamic> j) => RouteStopDetail(
        stopSequence: j['stop_sequence'] as int,
        terminalId: j['terminal_id'] as String,
        terminalName: j['terminal_name'] as String,
        city: j['city'] as String,
        offsetMinutes: j['offset_minutes'] as int? ?? 0,
      );
}

class TripRepository {
  TripRepository(this._api);
  final ApiClient _api;

  /// Terminals in route order, for the origin and destination pickers.
  Future<List<TerminalStop>> terminals() async {
    final json = await _api.get('/trips/terminals') as List<dynamic>;
    return json
        .map((e) => TerminalStop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Departures covering a journey on a given date.
  ///
  /// Both stops are required. A trip has no single fare or availability
  /// until the journey is known, so there is nothing meaningful to return
  /// for "trips from Ecoland" on its own.
  Future<List<TripSummary>> search({
    required int boardingStop,
    required int alightingStop,
    DateTime? serviceDate,
  }) async {
    final date = serviceDate ?? DateTime.now();
    final json = await _api.get('/trips/search', query: {
      'boarding_stop': boardingStop,
      'alighting_stop': alightingStop,
      'service_date':
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
    }) as List<dynamic>;
    return json
        .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteStopDetail>> stops(String tripId) async {
    final json = await _api.get('/trips/$tripId/stops') as List<dynamic>;
    return json
        .map((e) => RouteStopDetail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Live availability for a journey.
  ///
  /// Deliberately a hint, not a reservation: it reads without locking, so
  /// the number can change between this call and the booking. The
  /// authoritative check happens under lock when the space is claimed.
  Future<int> availability({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
  }) async {
    final json = await _api.get('/bookings/availability', query: {
      'trip_id': tripId,
      'boarding_stop': boardingStop,
      'alighting_stop': alightingStop,
    }) as Map<String, dynamic>;
    return json['seats_available'] as int? ?? 0;
  }
}
