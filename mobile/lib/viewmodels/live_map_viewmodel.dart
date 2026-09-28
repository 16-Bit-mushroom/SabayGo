import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/tracking_repository.dart';
import '../data/repositories/trip_repository.dart';

/// Drives the passenger's live map for one trip.
///
/// Two sources, deliberately kept apart. The route nodes come from
/// `/trips/{id}/stops` and are static for the life of the screen — a
/// route is a fixed LTFRB path, so they are fetched once. The van's
/// position comes from NAHGM and is polled.
///
/// A trip with no position yet is the ordinary state of a van still at
/// the origin terminal, not a failure: the route still draws, and the
/// screen says the van has not begun reporting. Treating that 404 as an
/// error would leave a passenger staring at an error page for the entirely
/// normal ten minutes before departure.
class LiveMapViewModel extends ChangeNotifier {
  LiveMapViewModel({
    required TripRepository tripRepository,
    required TrackingRepository trackingRepository,
    required this.tripId,
    this.boardingStop,
    this.alightingStop,
  })  : _trips = tripRepository,
        _tracking = trackingRepository {
    _load();
  }

  final TripRepository _trips;
  final TrackingRepository _tracking;
  final String tripId;

  /// The passenger's own journey, so their boarding and alighting nodes
  /// can be distinguished from the rest of the route. Null on the
  /// cooperative's own view of a trip, which has no single passenger.
  final int? boardingStop;
  final int? alightingStop;

  /// How often the van's position is re-read. A van on a highway moves
  /// roughly 150 m in ten seconds, which is finer than the map is read at
  /// this zoom, and it keeps a screen left open for an hour to a few
  /// hundred requests rather than a few thousand.
  static const pollInterval = Duration(seconds: 10);

  List<RouteStopDetail> stops = const [];
  VanPosition? position;
  List<TrackPoint> trail = const [];

  bool isLoading = true;

  /// The route loaded but the van has not reported a position yet.
  bool isAwaitingFirstReport = false;

  /// Fatal to the screen — the route itself could not be loaded. A failed
  /// *position* poll does not set this: the last known fix stays on screen
  /// with its own age, which is more use than an error page.
  String? error;

  Timer? _timer;

  Future<void> _load() async {
    try {
      stops = await _trips.stops(tripId);
    } on ApiException catch (e) {
      error = e.message;
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      trail = await _tracking.history(tripId);
    } on ApiException {
      // The trail is context, not the point of the screen.
    }

    await _refreshPosition();
    isLoading = false;
    notifyListeners();

    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    await _refreshPosition();
    notifyListeners();
  }

  Future<void> _refreshPosition() async {
    try {
      final next = await _tracking.position(tripId);
      // The trail is extended locally rather than re-fetched: the history
      // endpoint returns the whole trip every time, and the only point
      // that can be new is the one just read.
      if (next.recordedAt != position?.recordedAt) {
        trail = [
          ...trail,
          TrackPoint(latitude: next.latitude, longitude: next.longitude),
        ];
      }
      position = next;
      isAwaitingFirstReport = false;
    } on NotFoundException {
      isAwaitingFirstReport = position == null;
    } on ApiException {
      // Transient. Keep the last known fix — it carries its own age, and
      // `isStale` will say so once it is too old to act on.
    }
  }

  /// Manual pull-to-refresh, for a passenger who does not want to wait
  /// out the interval.
  Future<void> refresh() async {
    await _refreshPosition();
    notifyListeners();
  }

  RouteStopDetail? get boardingNode => _nodeAt(boardingStop);
  RouteStopDetail? get alightingNode => _nodeAt(alightingStop);

  RouteStopDetail? _nodeAt(int? sequence) {
    if (sequence == null) return null;
    for (final s in stops) {
      if (s.stopSequence == sequence) return s;
    }
    return null;
  }

  /// True once the van has passed the passenger's boarding node — the
  /// point after which no amount of hurrying to the terminal helps.
  bool get hasPassedBoardingStop {
    final at = position?.nearestStopSequence;
    final mine = boardingStop;
    return at != null && mine != null && at > mine;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
