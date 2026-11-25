/// Build-time configuration.
///
/// The backend runs on the machine that serves the console (`./run.sh`:
/// port 8000 beside the console's 3001), so with no `API_BASE_URL` the
/// console dials the host its own page came from. One bundle then works
/// on every network and from every browser at the terminal -- the laptop's
/// own (127.0.0.1:3001) or the Cashier's (`http://<laptop>:3001`) -- and a
/// new venue never needs a rebuild; it used to, because the laptop's
/// address was compiled in. Pass `API_BASE_URL` only for a backend on
/// another host (a production domain).
///
///   flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
class AppConfig {
  static const String _built = String.fromEnvironment('API_BASE_URL');

  /// The backend's port on that host: 8000 unless `run.sh` was started
  /// with `SABAYGO_BACKEND_PORT` (another project holding 8000).
  static const int _port = int.fromEnvironment('API_PORT', defaultValue: 8000);

  static String get apiBaseUrl => _built.isNotEmpty
      ? _built
      : '${Uri.base.scheme}://${Uri.base.host}:$_port/api/v1';

  static const Duration requestTimeout = Duration(seconds: 10);

  /// Where the server serves `/media` (a van's photographs).
  static String get serverRoot => apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
}
