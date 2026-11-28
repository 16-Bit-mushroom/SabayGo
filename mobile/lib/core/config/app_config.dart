import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration.
///
/// The base URL is a `--dart-define` rather than a constant because the
/// same build has to reach three different hosts: an emulator sees the
/// host machine at 10.0.2.2, a physical handset needs the machine's LAN
/// address, and production needs a domain. Hardcoding any one of them
/// guarantees the other two break.
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
///
/// In a browser with no `API_BASE_URL`, the app dials the backend on the
/// host its own page came from, as the console does: the laptop serves
/// both, so one web build works on every network (`API_PORT` when
/// `run.sh` moved the backend off 8000).
class AppConfig {
  static const String _built = String.fromEnvironment('API_BASE_URL');
  static const int _port = int.fromEnvironment('API_PORT', defaultValue: 8000);

  static String get apiBaseUrl {
    if (_built.isNotEmpty) return _built;
    if (kIsWeb) return '${Uri.base.scheme}://${Uri.base.host}:$_port/api/v1';
    return 'http://192.168.1.8:8000/api/v1';
  }

  /// Requests that hang forever look identical to a frozen app. Ten
  /// seconds is long enough for a slow terminal connection and short
  /// enough that a dead server surfaces as an error, not a spinner.
  static const Duration requestTimeout = Duration(seconds: 10);

  static const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
}
