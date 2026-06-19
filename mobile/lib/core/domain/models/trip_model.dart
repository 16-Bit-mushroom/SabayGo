class TripModel {
  final String id;
  final String passengerId;
  final String driverName;
  final String origin;
  final String destination;
  final String status; // e.g., "Completed", "Cancelled", "Ongoing"
  final double fare;
  final String date;
  final String rideType; // e.g., "Solo", "Shared"

  TripModel({
    required this.id,
    required this.passengerId,
    required this.driverName,
    required this.origin,
    required this.destination,
    required this.status,
    required this.fare,
    required this.date,
    required this.rideType,
  });

  factory TripModel.fromMap(Map<String, dynamic> map) {
    return TripModel(
      id: map['id'],
      passengerId: map['passengerId'],
      driverName: map['driverName'],
      origin: map['origin'],
      destination: map['destination'],
      status: map['status'],
      fare: map['fare'],
      date: map['date'],
      rideType: map['rideType'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'passengerId': passengerId,
      'driverName': driverName,
      'origin': origin,
      'destination': destination,
      'status': status,
      'fare': fare,
      'date': date,
      'rideType': rideType,
    };
  }
}