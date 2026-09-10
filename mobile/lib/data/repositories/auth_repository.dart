import '../../core/network/api_client.dart';

/// Roles as the backend defines them.
///
/// `coopAdmin` maps to `coop_admin`, not `operator`: under LTFRB usage
/// an operator is the franchise holder — the CPC holder, usually the van
/// owner — which is a different party from cooperative office staff.
enum UserRole {
  passenger('passenger'),
  conductor('conductor'),
  driver('driver'),
  coopAdmin('coop_admin'),
  admin('admin');

  const UserRole(this.wire);
  final String wire;

  static UserRole fromWire(String value) => UserRole.values.firstWhere(
        (r) => r.wire == value,
        orElse: () => UserRole.passenger,
      );

  bool get isCrew =>
      this == UserRole.conductor || this == UserRole.driver;
  bool get isOffice =>
      this == UserRole.coopAdmin || this == UserRole.admin;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.role,
    required this.userId,
  });

  final String accessToken;
  final UserRole role;
  final String userId;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        role: UserRole.fromWire(json['role'] as String),
        userId: json['user_id'] as String,
      );
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.email,
    required this.role,
    required this.accountStatus,
    this.displayName,
  });

  final String userId;
  final String email;
  final UserRole role;
  final String accountStatus;
  final String? displayName;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        role: UserRole.fromWire(json['role'] as String),
        accountStatus: json['account_status'] as String,
        displayName: json['display_name'] as String?,
      );

  String get initials {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return email.substring(0, 1).toUpperCase();
    final parts = name.split(RegExp(r'\s+'));
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final json = await _api.post('/auth/login', body: {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    return AuthSession.fromJson(json as Map<String, dynamic>);
  }

  /// Passenger self-registration.
  ///
  /// Crew accounts are not creatable here — conductors, drivers and
  /// cooperative administrators are provisioned by the office, because
  /// employment is a cooperative decision rather than self-service.
  Future<AuthSession> register({
    required String email,
    required String phoneNumber,
    required String password,
    required String firstName,
    required String lastName,
    String? middleName,
    String? homeAddress,
    String? gender,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactNumber,
  }) async {
    final json = await _api.post('/auth/register', body: {
      'email': email.trim().toLowerCase(),
      'phone_number': phoneNumber.trim(),
      'password': password,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      if (middleName != null && middleName.isNotEmpty) 'middle_name': middleName,
      if (homeAddress != null && homeAddress.isNotEmpty)
        'home_address': homeAddress,
      if (gender != null) 'gender': gender,
      if (emergencyContactName != null && emergencyContactName.isNotEmpty)
        'emergency_contact_name': emergencyContactName,
      if (emergencyContactRelation != null &&
          emergencyContactRelation.isNotEmpty)
        'emergency_contact_relation': emergencyContactRelation,
      if (emergencyContactNumber != null && emergencyContactNumber.isNotEmpty)
        'emergency_contact_number': emergencyContactNumber,
    });
    return AuthSession.fromJson(json as Map<String, dynamic>);
  }

  Future<UserProfile> me() async {
    final json = await _api.get('/auth/me');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }
}