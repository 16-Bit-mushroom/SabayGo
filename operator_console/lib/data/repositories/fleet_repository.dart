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
    this.operatorName,
    this.validationStatus = 'pending',
    this.registeredRouteId,
    required this.hasCabinCamera,
    this.cameraDeviceId,
    this.cpcCaseNo,
    this.cpcNumber,
    this.cameraInstalledAt,
  });

  final String vanId;
  final String plateNumber;
  final String? brand;
  final String? model;
  final String? color;
  final int seatCapacity;
  final String operationalStatus; // active | maintenance | inactive
  /// The van's owner, who drives it.
  final String? operatorName;
  /// Only a validated van can be assigned to a trip (rev 468).
  final String validationStatus;
  final String? registeredRouteId;
  final bool hasCabinCamera;
  final String? cameraDeviceId;
  final String? cpcCaseNo;
  final String? cpcNumber;
  final DateTime? cameraInstalledAt;

  factory Van.fromJson(Map<String, dynamic> json) => Van(
        vanId: json['van_id'] as String,
        plateNumber: json['plate_number'] as String,
        brand: json['brand'] as String?,
        model: json['model'] as String?,
        color: json['color'] as String?,
        seatCapacity: json['seat_capacity'] as int,
        operationalStatus: json['operational_status'] as String,
        operatorName: json['operator_name'] as String?,
        validationStatus: json['validation_status'] as String? ?? 'pending',
        registeredRouteId: json['registered_route_id'] as String?,
        hasCabinCamera: json['has_cabin_camera'] as bool? ?? false,
        cameraDeviceId: json['camera_device_id'] as String?,
        cpcCaseNo: json['cpc_case_no'] as String?,
        cpcNumber: json['cpc_number'] as String?,
        cameraInstalledAt: json['camera_installed_at'] == null
            ? null
            : DateTime.parse(json['camera_installed_at'] as String),
      );
}

/// An A2Z staff account: Dispatcher, Cashier or Terminal Manager.
///
/// The operator -- the van owner, who always drives -- is not staff and
/// has no account; operators are roster records (migration 017).
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.email,
    this.phoneNumber,
    required this.role,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.employmentStatus,
    this.validationStatus = 'pending',
    this.cooperativeName,
    this.assignedTerminalId,
  });

  final String userId;
  final String email;
  final String? phoneNumber;
  final String role;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String employmentStatus; // active | suspended | inactive
  /// A Dispatcher's roster validation; only a validated one is assigned.
  final String validationStatus;
  final String? cooperativeName;
  final String? assignedTerminalId;

  String get fullName => '$firstName $lastName';

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        phoneNumber: json['phone_number'] as String?,
        role: json['role'] as String,
        firstName: json['first_name'] as String,
        middleName: json['middle_name'] as String?,
        lastName: json['last_name'] as String,
        employmentStatus: json['employment_status'] as String,
        validationStatus: json['validation_status'] as String? ?? 'pending',
        cooperativeName: json['cooperative_name'] as String?,
        assignedTerminalId: json['assigned_terminal_id'] as String?,
      );
}

/// A van owner on the member roster: no login, one van each (rev 468).
class OperatorRecord {
  const OperatorRecord({
    required this.operatorId,
    required this.fullName,
    required this.licenseNumber,
    this.vanId,
  });

  final String operatorId;
  final String fullName;
  final String licenseNumber;
  final String? vanId;

  factory OperatorRecord.fromJson(Map<String, dynamic> json) => OperatorRecord(
        operatorId: json['operator_id'] as String,
        fullName: json['full_name'] as String,
        licenseNumber: json['license_number'] as String,
        vanId: json['van_id'] as String?,
      );
}

class FleetRepository {
  FleetRepository(this._api);
  final ApiClient _api;

  Future<List<Van>> listVans() async {
    final json = await _api.get('/fleet/vans');
    return (json as List).map((e) => Van.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OperatorRecord>> listOperators() async {
    final json = await _api.get('/fleet/operators');
    return (json as List)
        .map((e) => OperatorRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Added Pending; the Terminal Manager validates the record separately.
  Future<OperatorRecord> createOperator({
    required String fullName,
    required String contactNumber,
    required String licenseNumber,
    required DateTime licenseExpiry,
  }) async {
    final json = await _api.post('/fleet/operators', body: {
      'full_name': fullName.trim(),
      'contact_number': contactNumber.trim(),
      'license_number': licenseNumber.trim(),
      'license_expiry': licenseExpiry.toIso8601String().substring(0, 10),
    });
    return OperatorRecord.fromJson(json as Map<String, dynamic>);
  }

  Future<Van> createVan({
    required String plateNumber,
    required String operatorId,
    String? brand,
    String? model,
    String? color,
    required int seatCapacity,
    String? registeredRouteId,
    bool hasCabinCamera = false,
  }) async {
    final json = await _api.post('/fleet/vans', body: {
      'plate_number': plateNumber.trim().toUpperCase(),
      'operator_id': operatorId,
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
    required String role, // dispatcher | cashier | terminal_manager
    required String firstName,
    required String lastName,
  }) async {
    final json = await _api.post('/fleet/crew', body: {
      'email': email.trim().toLowerCase(),
      'phone_number': phoneNumber.trim(),
      'password': password,
      'role': role,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
    });
    return StaffMember.fromJson(json as Map<String, dynamic>);
  }

  Future<void> setCrewStatus(String userId, String status) async {
    await _api.patch('/fleet/crew/$userId/status', query: {'status': status});
  }
}
