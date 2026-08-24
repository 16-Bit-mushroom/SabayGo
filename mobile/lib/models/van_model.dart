class VanModel {
  VanModel({
    required this.id,
    required this.plateNumber,
    required this.cpcNumber,         // UPDATED
    required this.cpcCaseNumber,     // NEW
    required this.brand,
    required this.model,
    required this.color,
    required this.registeredRouteNodeIds,
    this.capacity = 14,
    required this.status,
    this.photoUrls = const [],
  });

  final String id;
  final String plateNumber;
  final String cpcNumber;            // UPDATED
  final String cpcCaseNumber;        // NEW
  final String brand;
  final String model;
  final String color;
  final List<String> registeredRouteNodeIds;
  final int capacity;
  final VanStatus status;
  final List<String> photoUrls;

  VanModel copyWith({
    String? id,
    String? plateNumber,
    String? cpcNumber,
    String? cpcCaseNumber,
    String? brand,
    String? model,
    String? color,
    List<String>? registeredRouteNodeIds,
    int? capacity,
    VanStatus? status,
    List<String>? photoUrls,
  }) {
    return VanModel(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      cpcNumber: cpcNumber ?? this.cpcNumber,
      cpcCaseNumber: cpcCaseNumber ?? this.cpcCaseNumber,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      color: color ?? this.color,
      registeredRouteNodeIds: registeredRouteNodeIds ?? this.registeredRouteNodeIds,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      photoUrls: photoUrls ?? this.photoUrls,
    );
  }
}

enum VanStatus { active, maintenance, inactive }