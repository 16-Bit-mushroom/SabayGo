/// Build-time configuration.
///
/// The base URL is a `--dart-define` rather than a constant because the
/// same build has to reach three different hosts: an emulator sees the
/// host machine at 10.0.2.2, a physical handset needs the machine's LAN
/// address, and production needs a domain. Hardcoding any one of them
/// guarantees the other two break.
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.8:8000/api/v1',
  );

  /// Requests that hang forever look identical to a frozen app. Ten
  /// seconds is long enough for a slow terminal connection and short
  /// enough that a dead server surfaces as an error, not a spinner.
  static const Duration requestTimeout = Duration(seconds: 10);

  static const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
}
