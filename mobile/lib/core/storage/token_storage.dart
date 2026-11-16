import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token in OS-backed encrypted storage.
///
/// Deliberately not SharedPreferences: those are plain XML in the app's
/// data directory and readable by any process on a rooted device. Crew
/// handsets in the field are exactly the case where that matters, and a
/// stolen Dispatcher token can log walk-ins and submit remittances.
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
    // One write after another, never together. On the web each value is
    // encrypted with a key kept in browser storage; on a browser's first
    // login there is no key yet, and three writes at once each made one,
    // the last overwriting the others -- the token was then sealed with a
    // key that no longer existed, and the next page load signed the person
    // out (found in the 10 Nov alpha run).
    await _storage.write(key: _accessToken, value: accessToken);
    await _storage.write(key: _role, value: role);
    await _storage.write(key: _userId, value: userId);
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
