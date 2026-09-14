import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/operations_repository.dart';

/// The crew member's shift: their rostered trips, the one they are
/// working now, and the stop the van is currently at.
///
/// The stop matters because every scan is judged against it — a ticket
/// for Digos is refused at Ecoland — and a roadside pickup is anchored to
/// the last stop passed. One place to hold it, rather than each screen
/// asking again.
class ShiftViewModel extends ChangeNotifier {
  ShiftViewModel(this._ops);

  final OperationsRepository _ops;

  List<CrewTrip> trips = const [];
  bool isLoading = false;
  bool hasLoaded = false;
  String? error;

  CrewTrip? active;
  int currentStop = 1;

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
    if (active?.tripId != trip.tripId) currentStop = 1;
    active = trip;
    notifyListeners();
  }

  void setStop(int sequence) {
    currentStop = sequence;
    notifyListeners();
  }

  void markStatus(String status) {
    if (active == null) return;
    active = active!.copyWith(status: status);
    trips = [for (final t in trips) t.tripId == active!.tripId ? active! : t];
    notifyListeners();
  }
}
