import '../../core/network/api_client.dart';

class Van {
  const Van({
    required this.vanId,
    required this.plateNumber,
    this.brand,
    this.model,
    this.color,
    required this.seatCapacity,
    required this.operationalStatus,
    this.registeredRouteId,
    required this.hasCabinCamera,
  });

  final String vanId;
  final String plateNumber;
  final String? brand;
  final String? model;
  final String? color;
  final int seatCapacity;
  final String operationalStatus; // active | maintenance | inactive
  final String? registeredRouteId;
  final bool hasCabinCamera;

  factory Van.fromJson(Map<String, dynamic> json) => Van(
        vanId: json['van_id'] as String,
        plateNumber: json['plate_number'] as String,
        brand: json['brand'] as String?,
        model: json['model'] as String?,
        color: json['color'] as String?,
        seatCapacity: json['seat_capacity'] as int,
        operationalStatus: json['operational_status'] as String,
        registeredRouteId: json['registered_route_id'] as String?,
        hasCabinCamera: json['has_cabin_camera'] as bool? ?? false,
      );
}

/// A cooperative staff member -- conductor or driver.
///
/// The backend's crew-creation endpoint still accepts a stale "operator"
/// role literal left over from before the operator/coop_admin rename
/// (migration 010); there is no such Role in the domain any more, so this
/// console never offers it. Only conductor and driver are provisioned
/// here -- coop_admin accounts are not crew.
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.employmentStatus,
    this.licenseNumber,
  });

  final String userId;
  final String email;
  final String role;
  final String firstName;
  final String lastName;
  final String employmentStatus; // active | suspended | inactive
  final String? licenseNumber;

  String get fullName => '$firstName $lastName';

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        employmentStatus: json['employment_status'] as String,
        licenseNumber: json['license_number'] as String?,
      );
}

class FleetRepository {
  FleetRepository(this._api);
  final ApiClient _api;

  Future<List<Van>> listVans() async {
    final json = await _api.get('/fleet/vans');
    return (json as List).map((e) => Van.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Van> createVan({
    required String plateNumber,
    String? brand,
    String? model,
    String? color,
    required int seatCapacity,
    String? registeredRouteId,
    bool hasCabinCamera = false,
  }) async {
    final json = await _api.post('/fleet/vans', body: {
      'plate_number': plateNumber.trim().toUpperCase(),
      if (brand != null && brand.isNotEmpty) 'brand': brand,
      if (model != null && model.isNotEmpty) 'model': model,
      if (color != null && color.isNotEmpty) 'color': color,
      'seat_capacity': seatCapacity,
      if (registeredRouteId != null) 'registered_route_id': registeredRouteId,
      'has_cabin_camera': hasCabinCamera,
    });
    return Van.fromJson(json as Map<String, dynamic>);
  }

  Future<void> setVanStatus(String vanId, String status) async {
    await _api.patch('/fleet/vans/$vanId/status',
        body: {'operational_status': status});
  }

  Future<List<StaffMember>> listCrew({String? role}) async {
    final json = await _api.get('/fleet/crew', query: role != null ? {'role': role} : null);
    return (json as List)
        .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StaffMember> createCrew({
    required String email,
    required String phoneNumber,
    required String password,
    required String role, // conductor | driver
    required String firstName,
    required String lastName,
    String? licenseNumber,
    DateTime? licenseExpiryDate,
  }) async {
    final json = await _api.post('/fleet/crew', body: {
      'email': email.trim().toLowerCase(),
      'phone_number': phoneNumber.trim(),
      'password': password,
      'role': role,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      if (licenseNumber != null && licenseNumber.isNotEmpty)
        'license_number': licenseNumber,
      if (licenseExpiryDate != null)
        'license_expiry_date':
            '${licenseExpiryDate.year.toString().padLeft(4, '0')}-'
            '${licenseExpiryDate.month.toString().padLeft(2, '0')}-'
            '${licenseExpiryDate.day.toString().padLeft(2, '0')}',
    });
    return StaffMember.fromJson(json as Map<String, dynamic>);
  }

  Future<void> setCrewStatus(String userId, String status) async {
    await _api.patch('/fleet/crew/$userId/status', query: {'status': status});
  }
}
