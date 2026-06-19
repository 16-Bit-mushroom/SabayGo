import 'package:flutter/material.dart';
import '../../../../core/domain/models/trip_model.dart';
import '../interfaces/i_booking_repository.dart';
import '../infrastructure/booking_dto.dart';

// The absolute states of your booking flow
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

  // State variables to track user interactions
  String selectedRideId = 'eco_1'; // Defaults to Shared
  String selectedPaymentId = ''; // Defaults to GCash
  bool isPromoApplied = true; // Defaults to Promo ON

  // NEW: State variables for the route
  String? selectedPickup = "University of Mindanao - Matina"; 
  String? selectedDropoff = "SM City Davao"; 

  BookingStep currentStep = BookingStep.selectingRide;
  DriverMatchDTO? currentMatch;
  String? errorMessage;

  BookingViewModel(this._repository);

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
    currentStep = BookingStep.selectingRide; 
    selectedPaymentId = '';
    selectedRideId = 'eco_1';
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
      currentMatch = await _repository.findRide(pickup, dropoff);
      currentStep = BookingStep.matched;
    } catch (e) {
      errorMessage = "Failed to find a driver on this route.";
      currentStep = BookingStep.selectingPayment;
    } finally {
      notifyListeners();
    }
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
      date: "${DateTime.now().day} ${_getMonth(DateTime.now().month)} ${DateTime.now().year}", 
      rideType: selectedRideId == 'eco_1' ? "Shared" : "Solo", 
    );

    // Write to SQLite
    await _repository.saveTrip(newTrip);

    reset();
  }

  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}