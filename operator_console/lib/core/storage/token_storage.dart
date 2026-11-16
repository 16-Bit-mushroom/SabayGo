import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token.
///
/// On web, flutter_secure_storage falls back to browser storage guarded
/// by the Web Crypto API rather than OS keystore encryption -- there is
/// no equivalent on a browser tab -- which is an accepted tradeoff for a
/// console that only cooperative office staff use on office machines.
class TokenStorage {
  static const _accessToken = 'sabaygo_operator.access_token';
  static const _role = 'sabaygo_operator.role';
  static const _userId = 'sabaygo_operator.user_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

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
