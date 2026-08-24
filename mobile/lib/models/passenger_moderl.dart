class PassengerModel {
  PassengerModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.address,
    required this.gender,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.trustRating,
    required this.avatarUrl,
  });

  final String id;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String address;
  final String gender;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final double trustRating;
  final String avatarUrl;

  PassengerModel copyWith({
    String? email,
    String? phoneNumber,
    String? address,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) {
    return PassengerModel(
      id: id,
      fullName: fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      gender: gender,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      trustRating: trustRating,
      avatarUrl: avatarUrl,
    );
  }
}