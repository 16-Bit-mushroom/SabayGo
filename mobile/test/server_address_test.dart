import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_v2_uv_express/core/config/server_address.dart';

/// What a person types in Sign in > Server, to the address the app dials.
void main() {
  test('a bare address gets the backend port and the API path', () {
    expect(ServerAddress.parse('10.0.52.117'), 'http://10.0.52.117:8000/api/v1');
    expect(ServerAddress.parse(' 10.0.52.117 '), 'http://10.0.52.117:8000/api/v1');
  });

  test('a port or a whole URL is kept as typed', () {
    expect(ServerAddress.parse('10.0.52.117:9000'), 'http://10.0.52.117:9000/api/v1');
    expect(ServerAddress.parse('http://10.0.52.117:8000/api/v1/'), 'http://10.0.52.117:8000/api/v1');
    expect(ServerAddress.parse('https://sabaygo.example.ph'), 'https://sabaygo.example.ph/api/v1');
  });

  test('something that is not an address is refused', () {
    expect(ServerAddress.parse(''), isNull);
    expect(ServerAddress.parse('   '), isNull);
    expect(ServerAddress.parse('ftp://10.0.52.117'), isNull);
  });

  test('the settings line shows the address without the scheme or path', () {
    expect(ServerAddress.shown('http://10.0.52.117:8000/api/v1'), '10.0.52.117:8000');
  });
}
