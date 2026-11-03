import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/location/current_position.dart';
import '../core/network/api_exception.dart';
import '../data/repositories/booking_repository.dart';
import '../models/uv_trip_model.dart';

/// Drives the reservation screen against the real booking (brief rev 721).
///
/// Cash only: the passenger reserves, gives the booking code to the
/// Dispatcher at the terminal and pays there. The seat is Paid when the
/// Dispatcher says so, and the app learns it by asking the server -- it
/// never decides a payment itself. Status is whatever the server last
/// reported: the reservation response, a refresh, or a check-in reply.
class ReservationViewModel extends ChangeNotifier {
  ReservationViewModel({
    required BookingRepository repository,
    required UvTripModel bookedTrip,
    ReservationResult? reservation,
    BookingSummary? booking,
  })  : _repo = repository,
        trip = bookedTrip {
    if (booking != null) {
      _apply(booking);
    } else if (reservation != null) {
      bookingId = reservation.bookingId;
      bookingCode = reservation.bookingCode;
      fare = reservation.fare;
      status = reservation.status;
      paymentStatus = reservation.paymentStatus;
      canCancel = paymentStatus == 'unpaid';
      // The reserve reply has no pay-by time or check-in window; the
      // booking itself does.
      unawaited(refresh());
    } else {
      fare = bookedTrip.approximateFare;
    }
    // While the seat is unpaid, look now and then for the Dispatcher's
    // mark, so the passenger at the van door sees it turn Paid.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (hasLiveBooking && !isPaid && isActive) refresh();
    });
  }

  final BookingRepository _repo;
  final UvTripModel trip;
  Timer? _poll;

  String? bookingId;
  String bookingCode = '';
  double fare = 0;
  String status = 'confirmed';
  String paymentStatus = 'unpaid';
  DateTime? paidAt;
  bool canCancel = false;
  String? cancelReason;
  String? cancelLabel;
  /// When an unpaid seat is released (`unpaid_cutoff_min` before departure).
  DateTime? payBy;
  /// When check-in opens at this passenger's own stop.
  DateTime? checkinOpensAt;

  bool isRefreshing = false;
  bool isCancelling = false;
  bool isCheckingIn = false;
  bool isUndoingCheckIn = false;
  String? checkInMessage;
  String? error;

  bool get hasLiveBooking => bookingId != null;
  bool get isPaid => paymentStatus == 'paid';
  bool get isConfirmed => status == 'confirmed';
  bool get isCheckedIn => status == 'checked_in';
  bool get isBoarded => status == 'boarded';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => isConfirmed || isCheckedIn || isBoarded;
  bool get wasReleased => cancelReason == 'auto_release';
  bool get canCheckIn => hasLiveBooking && isConfirmed;
  bool get canUndoCheckIn => hasLiveBooking && isCheckedIn;

  void _apply(BookingSummary b) {
    bookingId = b.bookingId;
    bookingCode = b.bookingCode;
    fare = b.fare;
    status = b.status;
    paymentStatus = b.paymentStatus;
    paidAt = b.paidAt;
    canCancel = b.canCancel;
    cancelReason = b.cancelReason;
    cancelLabel = b.cancelLabel;
    payBy = b.payBy;
    checkinOpensAt = b.checkinOpensAt;
  }

  /// Ask the server where the reservation stands: Paid, released, cancelled.
  Future<void> refresh() async {
    final id = bookingId;
    if (id == null || isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    try {
      _apply(await _repo.byId(id));
    } on ApiException {
      // A missed refresh is not worth an error line; the next one comes.
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  /// Cancel an unpaid reservation. A paid one goes through the Dispatcher,
  /// who hands the cash back; the server refuses it here.
  Future<void> cancel() async {
    if (!hasLiveBooking || isCancelling) return;
    isCancelling = true;
    error = null;
    notifyListeners();
    try {
      await _repo.cancel(bookingId!);
      await refresh();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isCancelling = false;
      notifyListeners();
    }
  }

  /// Confirm presence at the boarding terminal.
  ///
  /// The server does the radius and time-window check and hands back a
  /// message written for a person to read, so it is shown as-is rather
  /// than replaced with a client-side guess. A check-in neither pays the
  /// seat nor saves it from the cutoff.
  Future<void> checkIn() async {
    if (!hasLiveBooking || isCheckingIn) return;
    isCheckingIn = true;
    checkInMessage = null;
    error = null;
    notifyListeners();

    try {
      final position = await _resolvePosition();
      final result = await _repo.checkIn(
        bookingId: bookingId!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );
      status = result['status'] as String? ?? status;
      checkInMessage = result['message'] as String?;
    } on PolicyViolationException catch (e) {
      // Too far, too early, or too late -- the server's wording says which.
      checkInMessage = e.message;
    } on ApiException catch (e) {
      error = e.message;
    } on LocationServiceDisabledException {
      error = 'Turn on location services to check in.';
    } on PermissionDeniedException {
      error = 'SabayGo needs location permission to check you in at the terminal.';
    } finally {
      isCheckingIn = false;
      notifyListeners();
    }
  }

  /// Withdraw the check-in (D.2). The booking goes back to `confirmed`
  /// and the button to check in again reappears.
  Future<void> undoCheckIn() async {
    if (!canUndoCheckIn || isUndoingCheckIn) return;
    isUndoingCheckIn = true;
    error = null;
    notifyListeners();

    try {
      final result = await _repo.undoCheckIn(bookingId!);
      status = result['status'] as String? ?? 'confirmed';
      checkInMessage = result['message'] as String?;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isUndoingCheckIn = false;
      notifyListeners();
    }
  }

  Future<Position> _resolvePosition() => CurrentPosition.resolve();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
