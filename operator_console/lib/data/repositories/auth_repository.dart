import '../../core/network/api_client.dart';

/// Roles as the backend defines them.
///
/// `coopAdmin` maps to `coop_admin`, not `operator`: under LTFRB usage an
/// operator is the franchise holder -- the CPC holder, usually the van
/// owner -- a different party from cooperative office staff. This console
/// is for `coop_admin` only.
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

  Future<UserProfile> me() async {
    final json = await _api.get('/auth/me');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }
}
