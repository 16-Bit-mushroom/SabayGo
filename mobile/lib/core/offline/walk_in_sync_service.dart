import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/operations_repository.dart';
import '../network/api_exception.dart';
import 'pending_walk_in.dart';
import 'walk_in_queue.dart';

/// The outcome of logging a walk-in: either it reached the server, or it
/// didn't and now sits in the offline queue.
class WalkInSubmission {
  const WalkInSubmission.submitted(WalkInResult this.result) : queued = false;
  const WalkInSubmission.queued()
      : result = null,
        queued = true;

  final WalkInResult? result;
  final bool queued;
}

/// Logs walk-ins over the network when possible, and queues them on
/// device otherwise -- the offline-capable conductor manifest (spec
/// section 2.3.5, Table 5's Walk-In Audit row). Scoped to walk-in
/// logging only: the rest of the manifest still needs a live server
/// round trip to view.
///
/// A submission is queued, not failed, on `NetworkException` (never
/// left the device) or `RequestTimeoutException` (left, but the
/// response never came back). Both are safe to retry automatically
/// because every attempt carries the same `client_request_id`, which
/// the backend dedupes on -- a retried request that actually landed the
/// first time returns the original booking instead of a second one.
class WalkInSyncService extends ChangeNotifier {
  WalkInSyncService(this._ops, {WalkInQueue? queue})
      : _queue = queue ?? WalkInQueue() {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) flush();
    });
  }

  final OperationsRepository _ops;
  final WalkInQueue _queue;
  late final StreamSubscription<List<ConnectivityResult>> _sub;

  final Map<String, List<PendingWalkIn>> _pendingByTrip = {};
  bool _flushing = false;

  List<PendingWalkIn> pendingFor(String tripId) =>
      List.unmodifiable(_pendingByTrip[tripId] ?? const []);

  int pendingCountFor(String tripId) => pendingFor(tripId).length;

  Future<void> loadPendingCounts() async {
    final items = await _queue.all();
    _pendingByTrip.clear();
    for (final item in items) {
      (_pendingByTrip[item.tripId] ??= []).add(item);
    }
    notifyListeners();
  }

  Future<WalkInSubmission> submitOrQueue({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
    String? name,
    String? phone,
    bool wantsReceipt = false,
    bool isRoadsidePickup = false,
    String? pickupLandmark,
    double? fareOverride,
    String? fareNote,
  }) async {
    final item = PendingWalkIn(
      clientRequestId: _newRequestId(),
      tripId: tripId,
      boardingStop: boardingStop,
      alightingStop: alightingStop,
      name: name,
      phone: phone,
      wantsReceipt: wantsReceipt,
      isRoadsidePickup: isRoadsidePickup,
      pickupLandmark: pickupLandmark,
      fareOverride: fareOverride,
      fareNote: fareNote,
      queuedAt: DateTime.now(),
    );
    try {
      final result = await _submit(item);
      return WalkInSubmission.submitted(result);
    } on NetworkException {
      await _enqueue(item);
      return const WalkInSubmission.queued();
    } on RequestTimeoutException {
      await _enqueue(item);
      return const WalkInSubmission.queued();
    }
  }

  Future<WalkInResult> _submit(PendingWalkIn item) => _ops.walkIn(
        tripId: item.tripId,
        boardingStop: item.boardingStop,
        alightingStop: item.alightingStop,
        name: item.name,
        phone: item.phone,
        wantsReceipt: item.wantsReceipt,
        isRoadsidePickup: item.isRoadsidePickup,
        pickupLandmark: item.pickupLandmark,
        fareOverride: item.fareOverride,
        fareNote: item.fareNote,
        clientRequestId: item.clientRequestId,
      );

  Future<void> _enqueue(PendingWalkIn item) async {
    await _queue.enqueue(item);
    (_pendingByTrip[item.tripId] ??= []).add(item);
    notifyListeners();
  }

  /// Replay the queue in the order items were logged. Stops at the first
  /// `NetworkException` -- still offline, nothing further will land
  /// either. A non-network failure (a genuine policy rejection, say)
  /// leaves that item queued rather than dropping it silently, so it
  /// stays visible for the conductor rather than looping forever.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (final item in await _queue.all()) {
        try {
          await _submit(item);
          await _queue.remove(item.clientRequestId);
          _pendingByTrip[item.tripId]
              ?.removeWhere((i) => i.clientRequestId == item.clientRequestId);
          notifyListeners();
        } on NetworkException {
          break;
        } on RequestTimeoutException {
          break;
        } on ApiException {
          // Left queued -- visible via pendingCountFor, not lost.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
