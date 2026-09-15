import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/booking_repository.dart';
import '../models/uv_trip_model.dart';

/// Drives the ticket screen against the real booking, not a mock.
///
/// Status is whatever the server last reported. The old prototype tracked
/// "at terminal" as a local bool the screen set itself — an app judging its
/// own geofence could report success from anywhere, so every status shown
/// here is either the reservation response or a later poll/check-in reply.
class TicketViewModel extends ChangeNotifier {
  TicketViewModel({
    required BookingRepository repository,
    required UvTripModel bookedTrip,
    ReservationResult? reservation,
    this.checkinOpensAt,
  })  : _repo = repository,
        trip = bookedTrip {
    if (reservation != null) {
      bookingId = reservation.bookingId;
      ticketNumber = reservation.ticketNumber;
      fare = reservation.fare;
      status = reservation.status;
      qrPayload = reservation.qrPayload;
    } else {
      // Opened from a history list rather than straight after reserving.
      // Nothing live to poll or act on until "My bookings" carries a real
      // booking id through instead of a mock.
      fare = bookedTrip.approximateFare;
    }

    if (isAwaitingPayment) _startPolling();
  }

  final BookingRepository _repo;
  final UvTripModel trip;

  String? bookingId;
  String ticketNumber = '';
  double fare = 0;
  String status = 'confirmed';
  String? qrPayload;

  bool isStartingCheckout = false;
  bool isCheckingIn = false;
  bool isUndoingCheckIn = false;
  bool isPolling = false;
  String? checkInMessage;
  /// From /bookings/{id}: when check-in opens at this passenger's own stop.
  DateTime? checkinOpensAt;
  String? error;

  Timer? _pollTimer;
  int _pollAttempts = 0;
  static const _maxPollAttempts = 30; // ~2 minutes at 4s each

  bool get hasLiveBooking => bookingId != null;
  bool get isAwaitingPayment => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCheckedIn => status == 'checked_in';
  bool get isBoarded => status == 'boarded';
  bool get isCancelled => status == 'cancelled';
  bool get canCheckIn => hasLiveBooking && isConfirmed;
  bool get canUndoCheckIn => hasLiveBooking && isCheckedIn;
  bool get hasUsableTicket =>
      qrPayload != null && !isAwaitingPayment && !isCancelled;

  /// Start a PayMongo checkout and open it in the browser.
  ///
  /// The booking is confirmed by the signed webhook, never by the app
  /// coming back from the browser — so this only opens the URL and starts
  /// polling for the server to change its mind about the status.
  Future<void> startCheckout() async {
    if (!hasLiveBooking || isStartingCheckout) return;
    isStartingCheckout = true;
    error = null;
    notifyListeners();

    try {
      final url = await _repo.startCheckout(bookingId!);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        error = 'Could not open the payment page.';
      } else {
        _startPolling();
      }
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isStartingCheckout = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    isPolling = true;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshStatus());
  }

  /// Manual retry once automatic polling has given up.
  void refreshStatus() {
    if (!hasLiveBooking) return;
    _startPolling();
  }

  Future<void> _refreshStatus() async {
    final id = bookingId;
    if (id == null) return;
    _pollAttempts++;
    try {
      final match = await _repo.byId(id);
      if (match.status != status ||
          match.qrPayload != qrPayload ||
          match.checkinOpensAt != checkinOpensAt) {
        status = match.status;
        qrPayload = match.qrPayload ?? qrPayload;
        checkinOpensAt = match.checkinOpensAt;
        notifyListeners();
      }
    } on ApiException {
      // Transient — keep polling rather than surfacing every hiccup.
    }

    if (!isAwaitingPayment || _pollAttempts >= _maxPollAttempts) {
      _pollTimer?.cancel();
      isPolling = false;
      notifyListeners();
    }
  }

  Future<void> cancelTicket() async {
    if (!hasLiveBooking) return;
    error = null;
    try {
      await _repo.cancel(bookingId!);
      status = 'cancelled';
      _pollTimer?.cancel();
      isPolling = false;
      notifyListeners();
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }

  /// Confirm presence at the boarding terminal.
  ///
  /// The server does the radius and time-window check and hands back a
  /// message written for a person to read, so it is shown as-is rather
  /// than replaced with a client-side guess.
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
      // Too far, too early, or too late — the server's wording says which.
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

  Future<Position> _resolvePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw const LocationServiceDisabledException();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw PermissionDeniedException('Location permission denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw PermissionDeniedException('Location permission permanently denied');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
