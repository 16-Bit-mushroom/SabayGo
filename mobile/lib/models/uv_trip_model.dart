import 'transit_node_model.dart';

enum TripStatus { scheduled, boarding, departed, full, cancelled }

class UvTripModel {
  UvTripModel({
    required this.id,
    required this.tripLabel,
    required this.departureTime,
    required this.origin,
    required this.destination,
    required this.boardingStop,
    required this.alightingStop,
    required this.availableSeats,
    required this.approximateFare,
    this.estimatedArrivalTime,
    this.totalSeats = 14,
    this.operatorName,
    this.plateNumber,
    this.status = TripStatus.scheduled,
    this.isLastTrip = false,
    this.isSpecialTrip = false,
  });

  final String id;
  final String tripLabel;
  final DateTime departureTime;

  /// Not returned by the search endpoint — a trip's arrival depends on
  /// which stop the passenger alights at, and the search response is
  /// already scoped to one journey. Derivable from the route's stop
  /// offsets when the detail view loads them.
  final DateTime? estimatedArrivalTime;

  final TransitNodeModel origin;
  final TransitNodeModel destination;

  /// Positions on the route. These are what the booking call sends —
  /// terminal IDs are for display, sequences are for the fare matrix and
  /// the seat inventory.
  final int boardingStop;
  final int alightingStop;

  /// LTFRB capacity for a UV Express unit. Note this is a *count*, not a
  /// seating chart: passengers are not assigned seat numbers, and the
  /// system tracks how much space is taken on each section of road.
  final int totalSeats;
  final int availableSeats;

  /// The cooperative. Absent from search results, which return the
  /// vehicle instead.
  final String? operatorName;
  final String? plateNumber;

  final double approximateFare;
  final TripStatus status;
  final bool isLastTrip;
  final bool isSpecialTrip;

  bool get isFull => availableSeats <= 0 || status == TripStatus.full;

  /// Worth flagging in the UI while there is still time to act on it.
  bool get isNearlyFull => availableSeats > 0 && availableSeats <= 3;

  double get occupancyRatio =>
      totalSeats == 0 ? 0 : 1 - (availableSeats / totalSeats);

  /// Build from a /trips/search result.
  ///
  /// Fare arrives as a decimal string rather than a JSON number so it is
  /// not rounded in transit; it is parsed once here.
  factory UvTripModel.fromApi(Map<String, dynamic> j) {
    final boarding = j['boarding_stop'] as int;
    final alighting = j['alighting_stop'] as int;
    final seats = j['seats_available'] as int? ?? 0;

    return UvTripModel(
      id: j['trip_id'] as String,
      tripLabel: j['trip_label'] as String? ?? j['route_name'] as String? ?? '',
      departureTime: DateTime.parse(j['departure_datetime'] as String),
      origin: TransitNodeModel(
        id: 'stop-$boarding',
        name: j['boarding_terminal'] as String? ?? '',
        area: '',
        stopSequence: boarding,
      ),
      destination: TransitNodeModel(
        id: 'stop-$alighting',
        name: j['alighting_terminal'] as String? ?? '',
        area: '',
        stopSequence: alighting,
      ),
      boardingStop: boarding,
      alightingStop: alighting,
      availableSeats: seats,
      approximateFare: double.parse(j['fare_amount'].toString()),
      plateNumber: j['plate_number'] as String?,
      isSpecialTrip: j['is_special_trip'] as bool? ?? false,
      status: seats <= 0 ? TripStatus.full : TripStatus.scheduled,
    );
  }

  UvTripModel copyWith({int? availableSeats, TripStatus? status}) {
    return UvTripModel(
      id: id,
      tripLabel: tripLabel,
      departureTime: departureTime,
      estimatedArrivalTime: estimatedArrivalTime,
      origin: origin,
      destination: destination,
      boardingStop: boardingStop,
      alightingStop: alightingStop,
      totalSeats: totalSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      operatorName: operatorName,
      plateNumber: plateNumber,
      approximateFare: approximateFare,
      status: status ?? this.status,
      isLastTrip: isLastTrip,
      isSpecialTrip: isSpecialTrip,
    );
  }
}