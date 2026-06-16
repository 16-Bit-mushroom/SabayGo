import 'package:flutter/material.dart';
import '../interfaces/i_booking_repository.dart';
import '../infrastructure/booking_dto.dart';

// The 4 absolute states of your booking flow
enum BookingStep {
  selectingRide,
  selectingPayment,
  matching,
  matched,
  inRide,
  completed,
}

class BookingViewModel extends ChangeNotifier {
  final IBookingRepository _repository;

  // -- NEW: State variables to track user interactions --
  String selectedRideId = 'eco_1'; // Defaults to Shared
  String selectedPaymentId = ''; // Defaults to GCash
  bool isPromoApplied = true; // Defaults to Promo ON

  BookingStep currentStep = BookingStep.selectingRide;
  DriverMatchDTO? currentMatch;
  String? errorMessage;

  BookingViewModel(this._repository);

  // -- NEW: Methods to update the state --
  void selectRide(String id) {
    selectedRideId = id;
    notifyListeners(); // Tells the UI to redraw the green highlight
  }

  void selectPaymentMethod(String id) {
    selectedPaymentId = id;
    notifyListeners(); // Tells the UI to move the checkmark
  }

  void togglePromo() {
    isPromoApplied = !isPromoApplied;
    notifyListeners(); // Tells the UI to turn the promo off/on
  }

  // Transition 1: Move from Ride Selection to Payment
  void proceedToPayment() {
    currentStep = BookingStep.selectingPayment;
    notifyListeners();
  }

  // Transition Back: From Payment back to Ride Selection
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

  // New: Completely resets the flow if the user cancels
  void cancelRide() {
    currentMatch = null;
    currentStep = BookingStep.selectingRide;
    notifyListeners();
  }

  // New: Transitions to the In-Ride screen
  void startRide() {
    currentStep = BookingStep.inRide;
    notifyListeners();
  }

  // Triggers the Gamified Summary Screen
  void completeRide() {
    currentStep = BookingStep.completed;
    notifyListeners();
  }

  // Closes the receipt and starts a fresh new booking loop
  void resetToHome() {
    currentStep = BookingStep.selectingRide;
    currentMatch = null;
    notifyListeners();
  }

  // Transition 2 & 3: Start the algorithm, then show the match
  Future<void> requestRide(String pickup, String dropoff) async {
    currentStep = BookingStep.matching;
    errorMessage = null;
    notifyListeners();

    try {
      currentMatch = await _repository.findRide(pickup, dropoff);
      currentStep = BookingStep.matched;
    } catch (e) {
      errorMessage = "Failed to find a driver on this route.";
      currentStep = BookingStep.selectingPayment;
    } finally {
      notifyListeners();
    }
  }
}
