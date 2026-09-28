import '../../core/network/api_client.dart';

/// When one of the stops ahead is expected, and how far off it is.
///
/// `eta` is null while the van is stationary: an arrival time computed
/// from a near-zero speed is nonsense, so the server reports the distance
/// and withholds the time rather than inventing one. The UI must show the
/// distance in that case, not a blank.
class StopEta {
  const StopEta({
    required this.stopSequence,
    required this.terminalId,
    required this.terminalName,
    required this.distanceM,
    this.eta,
    this.minutesAway,
  });

  final int stopSequence;
  final String terminalId;
  final String terminalName;
  final double distanceM;
  final DateTime? eta;
  final int? minutesAway;

  factory StopEta.fromJson(Map<String, dynamic> j) => StopEta(
        stopSequence: j['stop_sequence'] as int,
        terminalId: j['terminal_id'] as String,
        terminalName: j['terminal_name'] as String,
        distanceM: (j['distance_m'] as num).toDouble(),
        eta: j['eta'] == null ? null : DateTime.parse(j['eta'] as String),
        minutesAway: j['minutes_away'] as int?,
      );
}

/// Where a van is now, as NAHGM last matched it to the route.
class VanPosition {
  const VanPosition({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.isStale,
    required this.secondsSinceReport,
    required this.etas,
    this.plateNumber,
    this.speedKph,
    this.headingDeg,
    this.nearestStopSequence,
    this.nearestStopName,
    this.distanceToStopM,
  });

  final String tripId;
  final double latitude;
  final double longitude;
  final String? plateNumber;
  final double? speedKph;
  final double? headingDeg;

  /// The map-matched node: which stop on the route the van is nearest.
  final int? nearestStopSequence;
  final String? nearestStopName;
  final double? distanceToStopM;

  final DateTime recordedAt;

  /// The server's own judgement, against the `tracking_stale_after_seconds`
  /// policy. Not recomputed here: a stale fix shown as current would send
  /// a passenger walking to a terminal on the strength of a van that
  /// stopped reporting twenty minutes ago, and the threshold that decides
  /// that belongs to the cooperative, not to the handset.
  final bool isStale;
  final int secondsSinceReport;

  final List<StopEta> etas;

  StopEta? get nextStop => etas.isEmpty ? null : etas.first;

  factory VanPosition.fromJson(Map<String, dynamic> j) => VanPosition(
        tripId: j['trip_id'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        plateNumber: j['plate_number'] as String?,
        speedKph: (j['speed_kph'] as num?)?.toDouble(),
        headingDeg: (j['heading_deg'] as num?)?.toDouble(),
        nearestStopSequence: j['nearest_stop_sequence'] as int?,
        nearestStopName: j['nearest_stop_name'] as String?,
        distanceToStopM: (j['distance_to_stop_m'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(j['recorded_at'] as String),
        isStale: j['is_stale'] as bool? ?? false,
        secondsSinceReport: j['seconds_since_report'] as int? ?? 0,
        etas: (j['etas'] as List<dynamic>? ?? const [])
            .map((e) => StopEta.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One recorded fix on the trail already travelled.
class TrackPoint {
  const TrackPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory TrackPoint.fromJson(Map<String, dynamic> j) => TrackPoint(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );
}

/// Reads NAHGM's live tracking endpoints.
class TrackingRepository {
  TrackingRepository(this._api);
  final ApiClient _api;

  /// Latest fix for a trip, with ETAs for the stops still ahead.
  ///
  /// Throws [NotFoundException] when nothing has been reported yet —
  /// which is the normal state of a trip that has not left the terminal,
  /// not an error, so callers distinguish it from a real failure.
  Future<VanPosition> position(String tripId) async {
    final json = await _api.get('/tracking/trips/$tripId/position')
        as Map<String, dynamic>;
    return VanPosition.fromJson(json);
  }

  /// Breadcrumb trail, oldest first — the road already covered.
  Future<List<TrackPoint>> history(String tripId, {int limit = 500}) async {
    final json = await _api.get(
      '/tracking/trips/$tripId/history',
      query: {'limit': limit},
    ) as List<dynamic>;
    return json
        .map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
