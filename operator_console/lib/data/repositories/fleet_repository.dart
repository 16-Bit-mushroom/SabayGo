import 'dart:typed_data';

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
    this.photos = const {},
    this.importBatchId,
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
  /// front | rear | left | right -> the photo's address under /media.
  /// The van validates only with all four (brief 8).
  final Map<String, String> photos;
  final String? importBatchId;

  static const photoSides = ['front', 'rear', 'left', 'right'];
  bool get hasAllPhotos => photoSides.every(photos.containsKey);

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
        photos: {
          for (final side in photoSides)
            if (json['photo_${side}_url'] != null) side: json['photo_${side}_url'] as String,
        },
        importBatchId: json['import_batch_id'] as String?,
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
    this.contactNumber = '',
    this.licenseExpiry,
    this.licenseExpired = false,
    this.validationStatus = 'pending',
    this.plateNumber,
    this.importBatchId,
  });

  final String operatorId;
  final String fullName;
  final String licenseNumber;
  final String? vanId;
  final String contactNumber;
  final DateTime? licenseExpiry;
  final bool licenseExpired;
  final String validationStatus;
  final String? plateNumber;
  final String? importBatchId;

  factory OperatorRecord.fromJson(Map<String, dynamic> json) => OperatorRecord(
        operatorId: json['operator_id'] as String,
        fullName: json['full_name'] as String,
        licenseNumber: json['license_number'] as String,
        vanId: json['van_id'] as String?,
        contactNumber: json['contact_number'] as String? ?? '',
        licenseExpiry: json['license_expiry'] == null
            ? null
            : DateTime.parse(json['license_expiry'] as String),
        licenseExpired: json['license_expired'] as bool? ?? false,
        validationStatus: json['validation_status'] as String? ?? 'pending',
        plateNumber: json['plate_number'] as String?,
        importBatchId: json['import_batch_id'] as String?,
      );
}

/// One row of an import preview: what the file says and why it fails.
class ImportRow {
  const ImportRow({required this.row, required this.ok, required this.errors, required this.values});
  final int row;
  final bool ok;
  final List<String> errors;
  final Map<String, dynamic> values;

  factory ImportRow.fromJson(Map<String, dynamic> j) => ImportRow(
        row: j['row'] as int,
        ok: j['ok'] as bool,
        errors: [for (final e in j['errors'] as List) e.toString()],
        values: Map<String, dynamic>.from(j['values'] as Map),
      );
}

class ImportResult {
  const ImportResult({required this.passing, required this.failing, required this.rows, this.transferId});
  final int passing;
  final int failing;
  final List<ImportRow> rows;
  /// Set once saved: its rejected rows can be downloaded to correct.
  final String? transferId;

  factory ImportResult.fromJson(Map<String, dynamic> j) => ImportResult(
        passing: j['rows_passing'] as int,
        failing: j['rows_failing'] as int,
        rows: [for (final r in j['rows'] as List) ImportRow.fromJson(r as Map<String, dynamic>)],
        transferId: (j['transfer'] as Map<String, dynamic>?)?['transfer_id'] as String?,
      );
}

/// One import or export in the log (Data_Transfers).
class DataTransfer {
  const DataTransfer({
    required this.transferId,
    required this.direction,
    required this.recordType,
    required this.fileName,
    required this.rowsAccepted,
    required this.rowsRejected,
    required this.byName,
    required this.at,
    required this.hasRejected,
  });

  final String transferId;
  final String direction; // import | export
  final String recordType;
  final String fileName;
  final int rowsAccepted;
  final int rowsRejected;
  final String? byName;
  final DateTime at;
  final bool hasRejected;

  factory DataTransfer.fromJson(Map<String, dynamic> j) => DataTransfer(
        transferId: j['transfer_id'] as String,
        direction: j['direction'] as String,
        recordType: j['record_type'] as String,
        fileName: j['file_name'] as String,
        rowsAccepted: j['rows_accepted'] as int,
        rowsRejected: j['rows_rejected'] as int,
        byName: j['performed_by_name'] as String?,
        at: DateTime.parse(j['performed_at'] as String),
        hasRejected: j['error_file_url'] != null,
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

  // ------------------------------------------------- validation (brief 3)
  /// [kind] is operators, vans or crew. The Terminal Manager only, and not
  /// on a record they imported themselves.
  Future<void> validate(String kind, String id, String status) =>
      _api.patch('/fleet/$kind/$id/validation', body: {'validation_status': status});

  /// One of the van's four photographs; a new one returns a validated van
  /// to Pending.
  Future<void> uploadVanPhoto(String vanId, String side, Uint8List bytes, String filename) =>
      _api.upload('PUT', '/fleet/vans/$vanId/photos/$side',
          field: 'image', bytes: bytes, filename: filename);

  // ------------------------------------------- import and export (brief 8)
  Future<Uint8List> template(String recordType, String format) =>
      _api.getBytes('/roster/templates/$recordType', query: {'format': format});

  /// Checks every row and saves nothing.
  Future<ImportResult> previewImport(String recordType, Uint8List bytes, String filename) async =>
      ImportResult.fromJson(await _api.upload('POST', '/roster/import/$recordType/preview',
          field: 'file', bytes: bytes, filename: filename) as Map<String, dynamic>);

  /// The same file again, re-checked; passing rows are saved Pending.
  Future<ImportResult> confirmImport(String recordType, Uint8List bytes, String filename) async =>
      ImportResult.fromJson(await _api.upload('POST', '/roster/import/$recordType',
          field: 'file', bytes: bytes, filename: filename) as Map<String, dynamic>);

  Future<Uint8List> export(String recordType, {required String format, required String purpose}) =>
      _api.getBytes('/roster/export/$recordType', query: {'format': format, 'purpose': purpose});

  Future<List<DataTransfer>> transfers() async => [
        for (final t in await _api.get('/roster/transfers') as List)
          DataTransfer.fromJson(t as Map<String, dynamic>)
      ];

  Future<Uint8List> rejectedRows(String transferId) =>
      _api.getBytes('/roster/transfers/$transferId/rejected');
}
