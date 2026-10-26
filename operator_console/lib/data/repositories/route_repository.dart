import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';

/// A terminal (Table 1): where vans load and passengers alight.
class Terminal {
  const Terminal({
    required this.terminalId,
    required this.name,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.geofenceM,
    required this.isStaffed,
    required this.isActive,
    required this.routes,
  });

  final String terminalId;
  final String name;
  final String city;
  final String? address;
  final double latitude;
  final double longitude;
  /// Null: the default terminal zone from Rules & Settings applies.
  final int? geofenceM;
  final bool isStaffed;
  final bool isActive;
  /// Codes of the routes in service that stop here.
  final List<String> routes;

  factory Terminal.fromJson(Map<String, dynamic> j) => Terminal(
        terminalId: j['terminal_id'] as String,
        name: j['terminal_name'] as String,
        city: j['city'] as String,
        address: j['location_address'] as String?,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        geofenceM: j['geofence_radius_m'] as int?,
        isStaffed: j['is_staffed'] as bool,
        isActive: j['is_active'] as bool,
        routes: [for (final r in j['routes'] as List) r as String],
      );
}

/// What a terminal is, as the add and edit forms send it.
class TerminalDraft {
  const TerminalDraft({
    required this.name,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.geofenceM,
    required this.isStaffed,
    required this.isActive,
  });

  final String name;
  final String city;
  final String address;
  final double latitude;
  final double longitude;
  final int? geofenceM;
  final bool isStaffed;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'terminal_name': name,
        'city': city,
        'location_address': address,
        'latitude': latitude,
        'longitude': longitude,
        'geofence_radius_m': geofenceM,
        'is_staffed': isStaffed,
        'is_active': isActive,
      };
}

/// One row of a route's fare matrix (Table 27), dated when it takes effect.
class Fare {
  const Fare({
    required this.fromStop,
    required this.toStop,
    required this.amount,
    required this.effectiveFrom,
    required this.status,
  });

  final int fromStop;
  final int toStop;
  final double amount;
  final DateTime effectiveFrom;
  final String status; // in_force | scheduled | replaced

  factory Fare.fromJson(Map<String, dynamic> j) => Fare(
        fromStop: j['from_stop_sequence'] as int,
        toStop: j['to_stop_sequence'] as int,
        amount: double.parse(j['fare_amount'].toString()),
        effectiveFrom: DateTime.parse(j['effective_from'] as String),
        status: j['status'] as String,
      );
}

/// Terminals, routes and fares: the Terminal Manager's set-up of A2Z's
/// network. The routes themselves are read with `DispatchRepository.listRoutes`.
class RouteRepository {
  RouteRepository(this._api);
  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  Future<List<Terminal>> terminals() async => [
        for (final t in await _api.get('/config/terminals') as List)
          Terminal.fromJson(t as Map<String, dynamic>)
      ];

  Future<void> addTerminal(TerminalDraft t) => _api.post('/config/terminals', body: t.toJson());

  Future<void> editTerminal(String terminalId, TerminalDraft t) =>
      _api.put('/config/terminals/$terminalId', body: t.toJson());

  /// [stops] in order: (terminal, minutes after departure). Fixed once saved.
  Future<void> addRoute({
    required String code,
    required String name,
    required String ltfrbCaseNo,
    required List<(String, int)> stops,
  }) =>
      _api.post('/config/routes', body: {
        'route_code': code,
        'route_name': name,
        'ltfrb_case_no': ltfrbCaseNo,
        'stops': [
          for (var i = 0; i < stops.length; i++)
            {'terminal_id': stops[i].$1, 'stop_sequence': i + 1, 'offset_minutes': stops[i].$2}
        ],
      });

  Future<void> editRoute(String routeId,
          {required String name, required String ltfrbCaseNo, required bool isActive}) =>
      _api.put('/config/routes/$routeId',
          body: {'route_name': name, 'ltfrb_case_no': ltfrbCaseNo, 'is_active': isActive});

  Future<List<Fare>> fares(String routeId) async => [
        for (final f in await _api.get('/config/routes/$routeId/fares') as List)
          Fare.fromJson(f as Map<String, dynamic>)
      ];

  /// From the starting terminal (stop 1) to each drop-off in [amounts],
  /// taking effect on [from].
  Future<void> saveFares(String routeId, Map<int, String> amounts, DateTime from) =>
      _api.post('/config/fares', body: {
        'route_id': routeId,
        'fares': [
          for (final e in amounts.entries)
            {
              'from_stop_sequence': 1,
              'to_stop_sequence': e.key,
              'fare_amount': e.value,
              'effective_from': _day.format(from),
            }
        ],
      });
}
