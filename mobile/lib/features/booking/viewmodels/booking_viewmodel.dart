import 'package:flutter/material.dart';
import '../../../../core/domain/models/trip_model.dart';
import '../interfaces/i_booking_repository.dart';
import '../infrastructure/booking_dto.dart';

// The absolute states of your booking flow
enum BookingStep {
  idle,
  selectingRide,
  selectingPayment,
  matching,
  matched,
  inRide,
  completed,
}

class BookingViewModel extends ChangeNotifier {
  final IBookingRepository _repository;

  // State variables to track user interactions
  String selectedRideId = ''; // Defaults to Shared
  String selectedPaymentId = ''; // Defaults to GCash
  bool isPromoApplied = true; // Defaults to Promo ON

  // NEW: State variables for the route
  String? selectedPickup = "University of Mindanao - Matina";
  String? selectedDropoff = "SM City Davao";

  BookingStep currentStep = BookingStep.idle;
  DriverMatchDTO? currentMatch;
  String? errorMessage;

  BookingViewModel(this._repository);

  // 3. Add this new method right below your constructor
  void setRouteAndSelectRide(String pickup, String dropoff) {
    selectedPickup = pickup;
    selectedDropoff = dropoff;
    currentStep = BookingStep.selectingRide;
    notifyListeners();
  }

  void selectRide(String id) {
    selectedRideId = id;
    notifyListeners();
  }

  void selectPaymentMethod(String id) {
    selectedPaymentId = id;
    notifyListeners();
  }

  void togglePromo() {
    isPromoApplied = !isPromoApplied;
    notifyListeners();
  }

  void proceedToPayment() {
    currentStep = BookingStep.selectingPayment;
    notifyListeners();
  }

  void stepBack() {
    if (currentStep == BookingStep.selectingPayment) {
      currentStep = BookingStep.selectingRide;
    } else if (currentStep == BookingStep.matched) {
      currentStep = BookingStep.selectingPayment;
    } else if (currentStep == BookingStep.inRide) {
      currentStep = BookingStep.matched;
    }
    notifyListeners();
  }

  void cancelRide() {
    currentMatch = null;
    currentStep = BookingStep.selectingRide;
    notifyListeners();
  }

  void startRide() {
    currentStep = BookingStep.inRide;
    notifyListeners();
  }

  void resetToHome() {
    currentStep = BookingStep.selectingRide;
    currentMatch = null;
    notifyListeners();
  }

  void reset() {
    currentStep = BookingStep.idle;
    selectedPaymentId = '';
    selectedRideId = '';
    isPromoApplied = false;
    currentMatch = null;
    notifyListeners();
  }

  Future<void> requestRide(String pickup, String dropoff) async {
    currentStep = BookingStep.matching;
    errorMessage = null;

    // Update the route state
    selectedPickup = pickup;
    selectedDropoff = dropoff;
    notifyListeners();

    try {
      // 1. Simulate the NAHGM Algorithm execution time
      await Future.delayed(const Duration(seconds: 3));

      // 2. Mock a guaranteed successful match for the defense demo
      currentMatch = DriverMatchDTO(
        driverName: "Carl Fernandez",
        vehicleModel: "Toyota Vios - Silver",
        vehiclePlate: "DVO 1234",
        driverRating: 4.9,
        fare: 0.0,
        etaMinutes: 5, // Fare is now calculated at the end via P2P
      );

      currentStep = BookingStep.matched;
    } catch (e) {
      errorMessage = "Failed to find a driver on this route.";
      currentStep = BookingStep.idle; // Send them back to idle, not payment
    } finally {
      notifyListeners();
    }
  }

  // NEW: Transition to the receipt screen
  void finishRide() {
    currentStep = BookingStep.completed;
    notifyListeners();
  }

  // FIXED: Removed duplicates, added the underscore to _repository
  Future<void> completeRide(String passengerId) async {
    if (currentMatch == null) return;

    final newTrip = TripModel(
      id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      passengerId: passengerId,
      driverName: currentMatch!.driverName,
      origin: selectedPickup ?? "Unknown Origin",
      destination: selectedDropoff ?? "Unknown Destination",
      status: "Completed",
      fare: currentMatch!.fare,
      date:
          "${DateTime.now().day} ${_getMonth(DateTime.now().month)} ${DateTime.now().year}",
      rideType: selectedRideId == 'eco_1' ? "Shared" : "Solo",
    );

    // Write to SQLite
    await _repository.saveTrip(newTrip);

    reset();
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
