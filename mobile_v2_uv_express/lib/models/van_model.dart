class VanModel {
  VanModel({
    required this.id,
    required this.plateNumber,
    required this.registeredRouteNodeIds,
    this.capacity = 14, // Hardcoded standard based on interview
    required this.status,
  });

  final String id;
  final String plateNumber;
  final List<String> registeredRouteNodeIds; // LTFRB approved stops
  final int capacity;
  final VanStatus status;
}

enum VanStatus { active, maintenance, inactive }