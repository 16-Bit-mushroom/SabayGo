import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_v2_uv_express/core/network/api_client.dart';
import 'package:mobile_v2_uv_express/core/storage/token_storage.dart';
import 'package:mobile_v2_uv_express/data/repositories/auth_repository.dart';
import 'package:mobile_v2_uv_express/viewmodels/auth_provider.dart';

/// Storage that fails the way flutter_secure_storage does on web when its
/// key no longer matches what is stored: an exception that is not an
/// ApiException.
class _BrokenTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => throw StateError('cannot decrypt');

  @override
  Future<void> clear() async => throw StateError('cannot clear either');
}

/// Storage that holds a token, for a server that answers with something
/// the profile parser cannot read.
class _StoredTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'tok';

  @override
  Future<void> clear() async {}
}

AuthProvider _auth(TokenStorage tokens, MockClient client) => AuthProvider(
      repository: AuthRepository(
          ApiClient(tokenStorage: tokens, httpClient: client, baseUrl: 'http://x/api/v1')),
      tokens: tokens,
    );

void main() {
  // Both used to leave the status at `unknown` -- the launch splash
  // spinner, with no way off it.
  test('unreadable storage on launch lands on sign-in, not the splash', () async {
    final auth = _auth(_BrokenTokens(), MockClient((_) async => http.Response('{}', 200)));
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
  });

  test('an unparseable profile on launch lands on sign-in, not the splash', () async {
    final auth = _auth(_StoredTokens(), MockClient((_) async => http.Response('{"user_id": 1}', 200)));
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
  });
}
