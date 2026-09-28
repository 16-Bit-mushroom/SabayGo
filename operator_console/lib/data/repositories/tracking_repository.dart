import '../../core/network/api_client.dart';

/// One van currently reporting, as `/tracking/fleet` returns it.
class FleetVan {
  const FleetVan({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.isStale,
    this.plateNumber,
    this.tripLabel,
    this.nearestStopName,
    this.speedKph,
    this.nextEta,
  });

  final String tripId;
  final double latitude;
  final double longitude;

  /// The server's judgement against the `tracking_stale_after_seconds`
  /// policy, not a local guess. Dispatch acts on this -- a van shown as
  /// live when it stopped reporting half an hour ago is worse than one
  /// shown as silent.
  final bool isStale;

  final String? plateNumber;
  final String? tripLabel;

  /// The map-matched node: which stop on its route the van is nearest.
  final String? nearestStopName;
  final double? speedKph;
  final DateTime? nextEta;

  String get label => plateNumber ?? tripLabel ?? tripId;

  factory FleetVan.fromJson(Map<String, dynamic> json) => FleetVan(
        tripId: json['trip_id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        isStale: json['is_stale'] as bool? ?? false,
        plateNumber: json['plate_number'] as String?,
        tripLabel: json['trip_label'] as String?,
        nearestStopName: json['nearest_stop_name'] as String?,
        speedKph: (json['speed_kph'] as num?)?.toDouble(),
        nextEta: json['next_eta'] == null
            ? null
            : DateTime.parse(json['next_eta'] as String),
      );
}

/// A node on a route, with the coordinate NAHGM map-matches against.
class RouteNode {
  const RouteNode({
    required this.stopSequence,
    required this.terminalName,
    required this.latitude,
    required this.longitude,
  });

  final int stopSequence;
  final String terminalName;
  final double latitude;
  final double longitude;

  factory RouteNode.fromJson(Map<String, dynamic> json) => RouteNode(
        stopSequence: json['stop_sequence'] as int,
        terminalName: json['terminal_name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}

class TrackingRepository {
  TrackingRepository(this._api);
  final ApiClient _api;

  /// Every van on a boarding or departed trip that has reported a
  /// position. Trips with no fix at all are omitted by the server.
  Future<List<FleetVan>> activeFleet() async {
    final json = await _api.get('/tracking/fleet') as List<dynamic>;
    return json
        .map((e) => FleetVan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The nodes of a trip's route, for drawing the path a selected van is
  /// working through.
  Future<List<RouteNode>> routeNodes(String tripId) async {
    final json = await _api.get('/trips/$tripId/stops') as List<dynamic>;
    return json
        .map((e) => RouteNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
