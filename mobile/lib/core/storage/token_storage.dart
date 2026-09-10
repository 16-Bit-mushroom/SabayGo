import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token in OS-backed encrypted storage.
///
/// Deliberately not SharedPreferences: those are plain XML in the app's
/// data directory and readable by any process on a rooted device. Crew
/// handsets in the field are exactly the case where that matters, and a
/// stolen conductor token can log walk-ins and submit remittances.
class TokenStorage {
  static const _accessToken = 'sabaygo.access_token';
  static const _role = 'sabaygo.role';
  static const _userId = 'sabaygo.user_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Read once, then cached: ApiClient reads the token on every request,
  // and hitting the keystore each time adds latency for no benefit.
  String? _cachedToken;

  Future<void> save({
    required String accessToken,
    required String role,
    required String userId,
  }) async {
    _cachedToken = accessToken;
    await Future.wait([
      _storage.write(key: _accessToken, value: accessToken),
      _storage.write(key: _role, value: role),
      _storage.write(key: _userId, value: userId),
    ]);
  }

  Future<String?> readAccessToken() async {
    return _cachedToken ??= await _storage.read(key: _accessToken);
  }

  Future<String?> readRole() => _storage.read(key: _role);

  Future<String?> readUserId() => _storage.read(key: _userId);

  Future<bool> hasSession() async => (await readAccessToken()) != null;

  Future<void> clear() async {
    _cachedToken = null;
    await Future.wait([
      _storage.delete(key: _accessToken),
      _storage.delete(key: _role),
      _storage.delete(key: _userId),
    ]);
  }
}
