import 'dart:typed_data';

import '../../core/network/api_client.dart';

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);
double? _num(Object? v) => v == null ? null : double.parse(v.toString());

/// One van on the Van Status Board (brief 8).
class VanStatus {
  const VanStatus({
    required this.vanId,
    required this.plateNumber,
    required this.operatorName,
    required this.operatorLicence,
    required this.operationalStatus,
    required this.state,
    required this.owes,
    required this.tripId,
    required this.tripLabel,
    required this.routeName,
    required this.tripStatus,
    required this.departure,
    required this.dispatcherName,
    required this.aboard,
    required this.latitude,
    required this.longitude,
    required this.positionAt,
    required this.positionStale,
    required this.nearestStopName,
  });

  final String vanId;
  final String plateNumber;
  final String operatorName;
  final String operatorLicence;
  final String operationalStatus;
  final String state; // travelling | out_of_service | on_site | not_on_trip
  final double owes;
  final String? tripId;
  final String? tripLabel;
  final String? routeName;
  final String? tripStatus;
  final DateTime? departure;
  final String? dispatcherName;
  /// The phone's door count; null without a phone.
  final int? aboard;
  final double? latitude;
  final double? longitude;
  final DateTime? positionAt;
  final bool? positionStale;
  final String? nearestStopName;

  factory VanStatus.fromJson(Map<String, dynamic> j) => VanStatus(
        vanId: j['van_id'] as String,
        plateNumber: j['plate_number'] as String,
        operatorName: j['operator_name'] as String,
        operatorLicence: j['operator_licence'] as String,
        operationalStatus: j['operational_status'] as String,
        state: j['state'] as String,
        owes: double.parse(j['owes'].toString()),
        tripId: j['trip_id'] as String?,
        tripLabel: j['trip_label'] as String?,
        routeName: j['route_name'] as String?,
        tripStatus: j['trip_status'] as String?,
        departure: _time(j['departure_datetime']),
        dispatcherName: j['dispatcher_name'] as String?,
        aboard: j['aboard'] as int?,
        latitude: _num(j['latitude']),
        longitude: _num(j['longitude']),
        positionAt: _time(j['position_at']),
        positionStale: j['position_stale'] as bool?,
        nearestStopName: j['nearest_stop_name'] as String?,
      );
}

/// A trip's door events to review (brief 9, Boarding Audit).
class TripAudit {
  const TripAudit({
    required this.tripId,
    required this.tripLabel,
    required this.departure,
    required this.status,
    required this.plateNumber,
    required this.operatorName,
    required this.operatorLicence,
    required this.dispatcherName,
    required this.crewAboard,
    required this.departedWithMore,
    required this.chainEvents,
    required this.chainVerified,
    required this.chainBrokenAt,
    required this.unlisted,
    required this.capacityAlerts,
  });

  final String tripId;
  final String tripLabel;
  final DateTime departure;
  final String status;
  final String? plateNumber;
  final String? operatorName;
  final String? operatorLicence;
  final String? dispatcherName;
  final bool crewAboard;
  final String? departedWithMore;
  final int chainEvents;
  final bool chainVerified;
  final int? chainBrokenAt;
  final List<UnlistedBoarding> unlisted;
  final List<CapacityAlert> capacityAlerts;

  factory TripAudit.fromJson(Map<String, dynamic> j) => TripAudit(
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String,
        departure: DateTime.parse(j['departure_datetime'] as String),
        status: j['status'] as String,
        plateNumber: j['plate_number'] as String?,
        operatorName: j['operator_name'] as String?,
        operatorLicence: j['operator_licence'] as String?,
        dispatcherName: j['dispatcher_name'] as String?,
        crewAboard: j['crew_aboard'] as bool,
        departedWithMore: j['departed_with_more'] as String?,
        chainEvents: j['chain_events'] as int,
        chainVerified: j['chain_verified'] as bool,
        chainBrokenAt: j['chain_broken_at'] as int?,
        unlisted: [for (final u in j['unlisted'] as List) UnlistedBoarding.fromJson(u as Map<String, dynamic>)],
        capacityAlerts: [
          for (final c in j['capacity_alerts'] as List) CapacityAlert.fromJson(c as Map<String, dynamic>)
        ],
      );
}

class UnlistedBoarding {
  const UnlistedBoarding({
    required this.eventId,
    required this.at,
    required this.resolution,
    required this.note,
    required this.listedDestination,
    required this.resolvedBy,
    required this.hasSnapshot,
    required this.snapshotDeleted,
  });

  final String eventId;
  final DateTime at;
  final String resolution; // pending | listed | explained
  final String? note;
  final String? listedDestination;
  final String? resolvedBy;
  final bool hasSnapshot;
  final bool snapshotDeleted;

  factory UnlistedBoarding.fromJson(Map<String, dynamic> j) => UnlistedBoarding(
        eventId: j['event_id'] as String,
        at: DateTime.parse(j['event_at'] as String),
        resolution: j['resolution_status'] as String,
        note: j['resolution_note'] as String?,
        listedDestination: j['listed_destination'] as String?,
        resolvedBy: j['resolved_by'] as String?,
        hasSnapshot: j['has_snapshot'] as bool,
        snapshotDeleted: j['snapshot_deleted'] as bool,
      );
}

class CapacityAlert {
  const CapacityAlert({required this.at, required this.aboard, required this.capacity, this.place});
  final DateTime at;
  final int aboard;
  final int capacity;
  final String? place;

  factory CapacityAlert.fromJson(Map<String, dynamic> j) => CapacityAlert(
        at: DateTime.parse(j['event_at'] as String),
        aboard: j['aboard'] as int,
        capacity: j['seat_capacity'] as int,
        place: j['place'] as String?,
      );
}

/// A driving flag (brief 6.4): an indicator for review, not proof.
class DrivingFlag {
  const DrivingFlag({
    required this.id,
    required this.tripId,
    required this.tripLabel,
    required this.operatorName,
    required this.operatorLicence,
    required this.plateNumber,
    required this.type,
    required this.flagged,
    required this.start,
    required this.end,
    required this.durationS,
    required this.stretchNo,
    required this.place,
    required this.maxSpeed,
    required this.limit,
    required this.timeRatio,
    required this.nearestStopM,
    required this.reviewStatus,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewNote,
    required this.disputeStatus,
  });

  final String id;
  final String tripId;
  final String tripLabel;
  final String? operatorName;
  final String? operatorLicence;
  final String? plateNumber;
  final String type; // overspeed | slow_stretch | unscheduled_stop | en_route_stop
  final bool flagged;
  final DateTime start;
  final DateTime? end;
  final int? durationS;
  final int? stretchNo;
  final String? place;
  final double? maxSpeed;
  final double? limit;
  final double? timeRatio;
  final double? nearestStopM;
  final String reviewStatus; // open | reviewed | dismissed
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? disputeStatus;

  factory DrivingFlag.fromJson(Map<String, dynamic> j) => DrivingFlag(
        id: j['driving_event_id'] as String,
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String,
        operatorName: j['operator_name'] as String?,
        operatorLicence: j['operator_licence'] as String?,
        plateNumber: j['plate_number'] as String?,
        type: j['flag_type'] as String,
        flagged: j['flagged'] as bool,
        start: DateTime.parse(j['start_at'] as String),
        end: _time(j['end_at']),
        durationS: j['duration_s'] as int?,
        stretchNo: j['stretch_no'] as int?,
        place: j['place'] as String?,
        maxSpeed: _num(j['max_speed_kmh']),
        limit: _num(j['limit_kmh']),
        timeRatio: _num(j['time_ratio']),
        nearestStopM: _num(j['nearest_stop_dist_m']),
        reviewStatus: j['review_status'] as String,
        reviewedBy: j['reviewed_by'] as String?,
        reviewedAt: _time(j['reviewed_at']),
        reviewNote: j['review_note'] as String?,
        disputeStatus: j['dispute_status'] as String?,
      );
}

/// The Terminal Manager's fleet screens (brief 9): the Van Status Board,
/// Boarding Audit and driving flags.
class OversightRepository {
  OversightRepository(this._api);
  final ApiClient _api;

  Future<List<VanStatus>> vanBoard() async => [
        for (final v in await _api.get('/fleet/vans/board') as List)
          VanStatus.fromJson(v as Map<String, dynamic>)
      ];

  Future<List<TripAudit>> boardingAudit(String day) async => [
        for (final t in await _api.get('/boarding-audit', query: {'date': day}) as List)
          TripAudit.fromJson(t as Map<String, dynamic>)
      ];

  /// The blurred still: the Terminal Manager only (brief 4.5, T38).
  Future<Uint8List> snapshot(String eventId) => _api.getBytes('/door-events/$eventId/snapshot');

  Future<List<DrivingFlag>> drivingFlags({String? day, String? status}) async => [
        for (final f in await _api.get('/driving-flags', query: {
          if (day != null) 'date': day,
          if (status != null) 'status': status,
        }) as List)
          DrivingFlag.fromJson(f as Map<String, dynamic>)
      ];

  Future<void> reviewFlag(String id, {required String status, String? note}) =>
      _api.post('/driving-flags/$id/review',
          body: {'status': status, if (note != null && note.isNotEmpty) 'note': note});
}
