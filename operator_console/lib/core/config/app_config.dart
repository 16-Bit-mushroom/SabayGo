/// Build-time configuration.
///
/// Flutter Web has no LAN-IP emulator quirk to work around, but the
/// backend still runs on a machine the browser has to be told about, so
/// this stays a `--dart-define` rather than a constant.
///
///   flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  static const Duration requestTimeout = Duration(seconds: 10);
}
