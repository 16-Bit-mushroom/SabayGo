import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/operations_repository.dart';
import '../network/api_exception.dart';
import 'pending_walk_in.dart';
import 'seat_mark_queue.dart';
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

/// The outcome of a Mark as Paid or a cancel: done (with anything the
/// server wants the Dispatcher told), or queued on the device.
class SeatMarkSubmission {
  const SeatMarkSubmission.done(this.notice) : queued = false;
  const SeatMarkSubmission.queued()
      : notice = null,
        queued = true;

  final String? notice;
  final bool queued;
}

/// The Dispatcher's work that must survive a dead zone (brief rev 721,
/// 2.1): walk-ins, Mark as Paid and cancelling a reservation. Each goes
/// over the network when possible and is queued on the device otherwise,
/// then replayed when the connection returns. Viewing the list still
/// needs the server; the screen keeps the last list it loaded.
///
/// A submission is queued, not failed, on `NetworkException` (never
/// left the device) or `RequestTimeoutException` (left, but the
/// response never came back). Both are safe to retry automatically
/// because every attempt carries the same `client_request_id`, which
/// the backend dedupes on -- a retried request that actually landed the
/// first time returns the original booking instead of a second one.
class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService(this._ops, {WalkInQueue? queue, SeatMarkQueue? marks})
      : _queue = queue ?? WalkInQueue(),
        _marks = marks ?? SeatMarkQueue() {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) flush();
    });
  }

  final OperationsRepository _ops;
  final WalkInQueue _queue;
  final SeatMarkQueue _marks;
  late final StreamSubscription<List<ConnectivityResult>> _sub;

  final Map<String, List<PendingWalkIn>> _pendingByTrip = {};
  final Map<String, PendingSeatMark> _pendingMarks = {};
  final List<String> _notices = [];
  bool _flushing = false;

  /// Marks still on the device for this trip, by booking id.
  Map<String, PendingSeatMark> marksFor(String tripId) =>
      {for (final m in _pendingMarks.values) if (m.tripId == tripId) m.bookingId: m};

  /// What synced marks came back with (a seat restored, a seat gone, a
  /// refusal), for the screen to show once. Reading empties it.
  List<String> takeNotices() {
    final out = List<String>.of(_notices);
    _notices.clear();
    return out;
  }

  List<PendingWalkIn> pendingFor(String tripId) =>
      List.unmodifiable(_pendingByTrip[tripId] ?? const []);

  int pendingCountFor(String tripId) => pendingFor(tripId).length;

  Future<void> loadPendingCounts() async {
    if (!WalkInQueue.isSupported) return;
    final items = await _queue.all();
    _pendingByTrip.clear();
    for (final item in items) {
      (_pendingByTrip[item.tripId] ??= []).add(item);
    }
    _pendingMarks
      ..clear()
      ..addAll({for (final m in await _marks.all()) m.bookingId: m});
    notifyListeners();
  }

  /// The passenger handed over the fare: mark the seat Paid, now or when
  /// the connection returns.
  Future<SeatMarkSubmission> markPaidOrQueue({
    required String tripId,
    required String bookingId,
    required String label,
  }) =>
      _markOrQueue(PendingSeatMark(
          bookingId: bookingId, tripId: tripId, kind: 'paid', at: DateTime.now(), label: label));

  /// Cancel a seat, now or when the connection returns.
  Future<SeatMarkSubmission> cancelOrQueue({
    required String tripId,
    required String bookingId,
    required String label,
    required String reason,
  }) =>
      _markOrQueue(PendingSeatMark(
          bookingId: bookingId, tripId: tripId, kind: 'cancel', at: DateTime.now(), label: label, reason: reason));

  Future<SeatMarkSubmission> _markOrQueue(PendingSeatMark mark) async {
    try {
      return SeatMarkSubmission.done(await _submitMark(mark));
    } on NetworkException {
      await _enqueueMark(mark);
      return const SeatMarkSubmission.queued();
    } on RequestTimeoutException {
      await _enqueueMark(mark);
      return const SeatMarkSubmission.queued();
    }
  }

  Future<String?> _submitMark(PendingSeatMark mark) async {
    if (mark.isPaid) {
      return (await _ops.markPaid(mark.bookingId, paidAt: mark.at)).notice;
    }
    await _ops.dispatcherCancel(mark.bookingId, reason: mark.reason!);
    return null;
  }

  Future<void> _enqueueMark(PendingSeatMark mark) async {
    await _marks.enqueue(mark);
    _pendingMarks[mark.bookingId] = mark;
    notifyListeners();
  }

  Future<WalkInSubmission> submitOrQueue({
    required String tripId,
    required int boardingStop,
    required int alightingStop,
    String? name,
    String? phone,
    bool wantsReceipt = false,
  }) async {
    final item = PendingWalkIn(
      clientRequestId: _newRequestId(),
      tripId: tripId,
      boardingStop: boardingStop,
      alightingStop: alightingStop,
      name: name,
      phone: phone,
      wantsReceipt: wantsReceipt,
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
        queuedAsRoadside: item.queuedAsRoadside,
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
  /// stays visible for the Dispatcher rather than looping forever.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Marks first: a Paid mark that reaches the server before the cutoff
      // keeps the seat, and a walk-up may be waiting for a cancelled one.
      for (final mark in await _marks.all()) {
        try {
          final notice = await _submitMark(mark);
          if (notice != null) _notices.add(notice);
          await _dropMark(mark);
        } on NetworkException {
          return;
        } on RequestTimeoutException {
          return;
        } on ApiException catch (e) {
          // Refused for good (the list locked, the seat already gone):
          // a replay would be refused again, so it is dropped and the
          // Dispatcher is told why.
          _notices.add('${mark.label}: ${e.message}');
          await _dropMark(mark);
        }
      }
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

  Future<void> _dropMark(PendingSeatMark mark) async {
    await _marks.remove(mark.bookingId);
    _pendingMarks.remove(mark.bookingId);
    notifyListeners();
  }

  String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
