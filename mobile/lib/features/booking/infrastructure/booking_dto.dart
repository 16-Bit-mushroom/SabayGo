class DriverMatchDTO {
  final String driverName;
  final double driverRating;
  final String vehiclePlate;
  final String vehicleModel;
  final int etaMinutes;
  final double fare;

  DriverMatchDTO({
    required this.driverName,
    required this.driverRating,
    required this.vehiclePlate,
    required this.vehicleModel,
    required this.etaMinutes,
    required this.fare,
  });
}