class DriverModel {
  DriverModel({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    required this.professionalLicenseNo,
    required this.licenseExpiryDate,
    required this.cttmoIdNo,
    required this.status,
    this.cttmoIdPhotoUrl, // --- NEW FIELD ---
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String professionalLicenseNo;
  final DateTime licenseExpiryDate;
  final String cttmoIdNo;
  final DriverStatus status;
  final String? cttmoIdPhotoUrl; // --- NEW FIELD ---

  DriverModel copyWith({
    String? id,
    String? fullName,
    String? contactNumber,
    String? professionalLicenseNo,
    DateTime? licenseExpiryDate,
    String? cttmoIdNo,
    DriverStatus? status,
    String? cttmoIdPhotoUrl,
  }) {
    return DriverModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      contactNumber: contactNumber ?? this.contactNumber,
      professionalLicenseNo: professionalLicenseNo ?? this.professionalLicenseNo,
      licenseExpiryDate: licenseExpiryDate ?? this.licenseExpiryDate,
      cttmoIdNo: cttmoIdNo ?? this.cttmoIdNo,
      status: status ?? this.status,
      cttmoIdPhotoUrl: cttmoIdPhotoUrl ?? this.cttmoIdPhotoUrl,
    );
  }
}

enum DriverStatus { active, suspended, inactive }