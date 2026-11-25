import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Where the backend is: typed on a test phone, not only compiled in.
///
/// Test builds only. A released app has its server fixed (a domain) and
/// ignores anything saved here; passengers never type an address.
///
/// While the server is a laptop, its address changes with every network
/// (school, the terminal's Wi-Fi, a phone hotspot), and a compiled-in
/// address meant a rebuild at each venue. The build's `API_BASE_URL` is
/// now only the starting value. An address typed on the sign-in screen
/// replaces it and is kept, until a build made for a different address
/// is installed: whichever was chosen last wins, so `./run.sh --mobile`
/// on a new network is never overridden by an address typed at an older
/// one.
class ServerAddress {
  static const _chosen = 'sabaygo.server';
  static const _overrode = 'sabaygo.server_overrode';
  static const port = 8000;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// The address to start with: the one typed on this phone, unless the
  /// installed build was made for another address since.
  static Future<String> load() async {
    // A released app dials only the server it was built for.
    if (!AppConfig.isDebug) return AppConfig.apiBaseUrl;
    try {
      final chosen = await _storage.read(key: _chosen);
      final overrode = await _storage.read(key: _overrode);
      if (chosen != null && overrode == AppConfig.apiBaseUrl) return chosen;
    } catch (_) {
      // Unreadable storage is not a reason to stop the app opening.
    }
    return AppConfig.apiBaseUrl;
  }

  static Future<void> save(String apiBase) async {
    // One write after the other, as in TokenStorage (web key race).
    await _storage.write(key: _chosen, value: apiBase);
    await _storage.write(key: _overrode, value: AppConfig.apiBaseUrl);
  }

  /// `10.0.52.117`, `10.0.52.117:8000` or a whole URL, to the API base;
  /// null when it is not an address at all.
  static String? parse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : (uri.scheme == 'http' ? port : null),
      path: path.isEmpty ? '/api/v1' : path,
    ).toString();
  }

  /// The address without `/api/v1`, for the settings line.
  static String shown(String apiBase) =>
      apiBase.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/api/v1/?$'), '');

  /// Whether the server answers its health check within a few seconds.
  static Future<bool> answers(String apiBase) async {
    final root = apiBase.replaceFirst(RegExp(r'/api/v1/?$'), '');
    try {
      final r = await http.get(Uri.parse('$root/health')).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
