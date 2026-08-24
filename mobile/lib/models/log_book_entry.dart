class LogBookEntry {
  LogBookEntry({
    required this.id,
    required this.passengerName,
    required this.contactNumber,
    required this.address,
    required this.tripLabel,
    required this.destinationName,
    required this.vanPlateNumber,
    required this.date,
  });

  final String id;
  final String passengerName;
  final String contactNumber;
  final String address;
  final String tripLabel;
  final String destinationName;
  final String vanPlateNumber;
  final DateTime date;
}