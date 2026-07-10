import 'transit_node_model.dart';

enum TripStatus { scheduled, boarding, departed, full, cancelled }

class UvTripModel {
  UvTripModel({
    required this.id,
    required this.tripLabel,
    required this.departureTime,
    required this.estimatedArrivalTime, // ADDED
    required this.origin,
    required this.destination,
    required this.totalSeats,
    required this.availableSeats,
    required this.operatorName,
    required this.approximateFare, // ADDED
    this.status = TripStatus.scheduled,
    this.isLastTrip = false,
  });

  final String id;
  final String tripLabel; 
  final DateTime departureTime;
  final DateTime estimatedArrivalTime; // ADDED
  final TransitNodeModel origin;
  final TransitNodeModel destination;
  final int totalSeats;
  final int availableSeats;
  final String operatorName; 
  final double approximateFare; // ADDED
  final TripStatus status;
  final bool isLastTrip;

  bool get isFull => availableSeats <= 0 || status == TripStatus.full;
  double get occupancyRatio => totalSeats == 0 ? 0 : 1 - (availableSeats / totalSeats);

  UvTripModel copyWith({int? availableSeats, TripStatus? status}) {
    return UvTripModel(
      id: id,
      tripLabel: tripLabel,
      departureTime: departureTime,
      estimatedArrivalTime: estimatedArrivalTime, // ADDED
      origin: origin,
      destination: destination,
      totalSeats: totalSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      operatorName: operatorName,
      approximateFare: approximateFare, // ADDED
      status: status ?? this.status,
      isLastTrip: isLastTrip,
    );
  }
}