/// A passenger's own profile, as returned by `GET /auth/me`.
class PassengerModel {
  PassengerModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.phoneNumber,
    this.address,
    this.gender,
    this.emergencyContactName,
    this.emergencyContactRelation,
    this.emergencyContactPhone,
    this.trustRating,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? phoneNumber;
  final String? address;
  final String? gender;
  final String? emergencyContactName;
  final String? emergencyContactRelation;
  final String? emergencyContactPhone;
  final double? trustRating;
  final String? avatarUrl;

  String get fullName => '$firstName $lastName'.trim();

  /// Used wherever there is no photo to show — the tab bar, the profile
  /// header — instead of a network placeholder that fails offline.
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final combined = '$f$l'.toUpperCase();
    return combined.isNotEmpty ? combined : email.substring(0, 1).toUpperCase();
  }

  factory PassengerModel.fromApi(Map<String, dynamic> j) => PassengerModel(
        id: j['user_id'] as String,
        email: j['email'] as String,
        firstName: (j['first_name'] as String?) ?? '',
        lastName: (j['last_name'] as String?) ?? '',
        middleName: j['middle_name'] as String?,
        phoneNumber: j['phone_number'] as String?,
        address: j['home_address'] as String?,
        gender: j['gender'] as String?,
        emergencyContactName: j['emergency_contact_name'] as String?,
        emergencyContactRelation: j['emergency_contact_relation'] as String?,
        emergencyContactPhone: j['emergency_contact_number'] as String?,
        trustRating: (j['trust_rating'] as num?)?.toDouble(),
        avatarUrl: j['avatar_url'] as String?,
      );
}
