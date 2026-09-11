import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/booking_repository.dart';

class ReservationsViewModel extends ChangeNotifier {
  ReservationsViewModel(this._repo);

  final BookingRepository _repo;

  List<BookingSummary> _all = const [];
  bool isLoading = false;
  bool hasLoaded = false;
  String? error;

  /// Booking ids with a cancel or reschedule in flight, so the row can
  /// disable its own buttons without freezing the whole list.
  final Set<String> _busy = {};
  bool isBusy(String bookingId) => _busy.contains(bookingId);

  /// Soonest departure first: the one the passenger is about to take.
  List<BookingSummary> get active {
    final list = _all.where((b) => b.isActive).toList()
      ..sort((a, b) => a.departure.compareTo(b.departure));
    return list;
  }

  BookingSummary? get current => active.isEmpty ? null : active.first;
  List<BookingSummary> get upcoming =>
      active.length <= 1 ? const [] : active.sublist(1);

  List<BookingSummary> get history => _all
      .where((b) => !b.isActive && !b.isCancelled)
      .toList();

  List<BookingSummary> get cancelled =>
      _all.where((b) => b.isCancelled).toList();

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _all = await _repo.mine();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      hasLoaded = true;
      notifyListeners();
    }
  }

  /// Returns the server's message on failure, null on success.
  Future<String?> cancel(String bookingId) async {
    _busy.add(bookingId);
    notifyListeners();
    try {
      await _repo.cancel(bookingId);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _busy.remove(bookingId);
      notifyListeners();
    }
  }

  /// Returns the server's message on failure, null on success.
  Future<String?> reschedule(String bookingId, String newTripId) async {
    _busy.add(bookingId);
    notifyListeners();
    try {
      await _repo.reschedule(bookingId: bookingId, newTripId: newTripId);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _busy.remove(bookingId);
      notifyListeners();
    }
  }
}
