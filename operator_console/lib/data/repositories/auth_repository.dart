import '../../core/network/api_client.dart';

/// Roles as the backend defines them.
///
/// This console is for the office: the Terminal Manager and the Cashier.
/// Never "operator" for either -- under LTFRB usage the operator is the
/// franchise holder, here the van owner who drives, and has no account.
enum UserRole {
  passenger('passenger'),
  dispatcher('dispatcher'),
  terminalManager('terminal_manager'),
  cashier('cashier'),
  admin('admin');

  const UserRole(this.wire);
  final String wire;

  static UserRole fromWire(String value) => UserRole.values.firstWhere(
        (r) => r.wire == value,
        orElse: () => UserRole.passenger,
      );

  bool get isOffice =>
      this == UserRole.terminalManager || this == UserRole.cashier || this == UserRole.admin;

  /// Decides what is owed, sets rules, validates records. The Cashier
  /// records payments and does none of these (separation of duties).
  bool get isManager => this == UserRole.terminalManager || this == UserRole.admin;
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
    this.firstName,
    this.lastName,
    this.phoneNumber,
  });

  final String userId;
  final String email;
  final UserRole role;
  final String accountStatus;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        role: UserRole.fromWire(json['role'] as String),
        accountStatus: json['account_status'] as String,
        displayName: json['display_name'] as String?,
        firstName: json['first_name'] as String?,
        lastName: json['last_name'] as String?,
        phoneNumber: json['phone_number'] as String?,
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

  /// PATCH /auth/me. Only the fields given are changed. A new password
  /// needs the current one; a wrong current password comes back as a 409,
  /// deliberately not a 401, which would sign the office out.
  Future<UserProfile> updateMe({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? currentPassword,
    String? newPassword,
  }) async {
    final json = await _api.patch('/auth/me', body: {
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (newPassword != null) 'current_password': currentPassword,
      if (newPassword != null) 'new_password': newPassword,
    });
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }
}
