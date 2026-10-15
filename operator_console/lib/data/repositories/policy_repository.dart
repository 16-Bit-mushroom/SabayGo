import '../../core/network/api_client.dart';

/// A configurable cooperative policy row -- reschedule cutoff, advance
/// booking cap, geofence radius, hold TTL, variance threshold, and so on.
///
/// Existing trips are unaffected by an edit here: policy values are
/// snapshotted onto each trip at generation time, so a change here only
/// governs trips generated from this point forward.
class Policy {
  const Policy({
    required this.policyKey,
    required this.policyValue,
    required this.dataType,
    required this.description,
    required this.updatedAt,
    this.effectiveFrom,
    this.updatedBy,
  });

  final String policyKey;
  final String policyValue;
  final String dataType; // int | decimal | bool | string
  final String description;
  final DateTime updatedAt;
  final DateTime? effectiveFrom;
  /// Who set it (none for values set before the history began).
  final String? updatedBy;

  factory Policy.fromJson(Map<String, dynamic> json) => Policy(
        policyKey: json['policy_key'] as String,
        policyValue: json['policy_value'] as String,
        dataType: json['data_type'] as String,
        description: json['description'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        effectiveFrom: json['effective_from'] == null
            ? null
            : DateTime.parse(json['effective_from'] as String),
        updatedBy: json['updated_by_name'] as String?,
      );
}

class PolicyRepository {
  PolicyRepository(this._api);
  final ApiClient _api;

  Future<List<Policy>> list() async {
    final json = await _api.get('/config/policies');
    return (json as List).map((e) => Policy.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Policy> update(String policyKey, String value) async {
    final json = await _api.put('/config/policies/$policyKey', body: {
      'policy_value': value,
    });
    return Policy.fromJson(json as Map<String, dynamic>);
  }

  /// Every value the key has held, newest first, with who set it.
  Future<List<Policy>> history(String policyKey) async => [
        for (final p in await _api.get('/config/policies/$policyKey/history') as List)
          Policy.fromJson(p as Map<String, dynamic>)
      ];

  Future<List<RouteStretch>> stretches(String routeId) async => [
        for (final s in await _api.get('/config/routes/$routeId/stretches') as List)
          RouteStretch.fromJson(s as Map<String, dynamic>)
      ];

  /// One speed limit per stretch in route order, and the stops' zone.
  Future<List<RouteStretch>> saveStretches(String routeId,
          {required List<int> limits, required int stopZoneM}) async =>
      [
        for (final s in await _api.put('/config/routes/$routeId/stretches',
            body: {'speed_limits_kmh': limits, 'stop_zone_radius_m': stopZoneM}) as List)
          RouteStretch.fromJson(s as Map<String, dynamic>)
      ];
}

/// One stretch of a route, stop to stop, with A2Z's speed limit (brief 6.3).
class RouteStretch {
  const RouteStretch({
    required this.stretchNo,
    required this.fromStop,
    required this.toStop,
    required this.lengthM,
    required this.speedLimitKmh,
    required this.stopZoneM,
    required this.expectedTimeS,
  });

  final int stretchNo;
  final String fromStop;
  final String toStop;
  final double lengthM;
  final int speedLimitKmh;
  final int stopZoneM;
  final int expectedTimeS;

  factory RouteStretch.fromJson(Map<String, dynamic> j) => RouteStretch(
        stretchNo: j['stretch_no'] as int,
        fromStop: j['from_stop'] as String,
        toStop: j['to_stop'] as String,
        lengthM: double.parse(j['length_m'].toString()),
        speedLimitKmh: j['speed_limit_kmh'] as int,
        stopZoneM: j['stop_zone_radius_m'] as int,
        expectedTimeS: j['expected_time_s'] as int,
      );
}
