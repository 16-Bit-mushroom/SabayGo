import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/operations_repository.dart';

/// The crew member's shift: their assigned trips and the one they are
/// working now.
///
/// There is no "van is at" stop any more: every passenger boards at the
/// trip's starting terminal (rev 603, brief 2.4), so scans and walk-ins
/// are judged against that one stop (`CrewTrip.boardingStop`).
class ShiftViewModel extends ChangeNotifier {
  ShiftViewModel(this._ops);

  final OperationsRepository _ops;

  List<CrewTrip> trips = const [];
  bool isLoading = false;
  bool hasLoaded = false;
  String? error;

  CrewTrip? active;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      trips = await _ops.assignedTrips();
      // Keep the selection across a refresh, but pick up its new status.
      if (active != null) {
        CrewTrip? refreshed;
        for (final t in trips) {
          if (t.tripId == active!.tripId) refreshed = t;
        }
        active = refreshed;
      }
      // With exactly one trip today there is nothing to choose.
      if (active == null && trips.length == 1) active = trips.first;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      hasLoaded = true;
      notifyListeners();
    }
  }

  void select(CrewTrip trip) {
    active = trip;
    notifyListeners();
  }

  void markStatus(String status) {
    if (active == null) return;
    active = active!.copyWith(status: status);
    trips = [for (final t in trips) t.tripId == active!.tripId ? active! : t];
    notifyListeners();
  }
}
