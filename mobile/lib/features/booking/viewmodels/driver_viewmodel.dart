import 'package:flutter/material.dart';

// The definitive lifecycle of a driver's shift
enum DriverStep { 
  offline, 
  online, 
  requestReceived, 
  headingToPickup, 
  arrivedAtPickup, 
  inRide, 
  completed 
}

// A lightweight data class to hold incoming commuter requests
class MockRideRequest {
  final String id;
  final String commuterName;
  final double commuterRating;
  final String pickupNode;
  final String dropoffNode;
  final double estimatedFare;
  final String distance;

  MockRideRequest({
    required this.id,
    required this.commuterName,
    required this.commuterRating,
    required this.pickupNode,
    required this.dropoffNode,
    required this.estimatedFare,
    required this.distance,
  });
}

class DriverViewModel extends ChangeNotifier {
  DriverStep currentStep = DriverStep.offline;
  MockRideRequest? currentRequest;

  bool get isOnline => currentStep != DriverStep.offline;

  // 1. Toggle shift status
  void toggleStatus() {
    // If they go offline, wipe any pending state and shut down
    if (isOnline) {
      currentStep = DriverStep.offline;
      currentRequest = null;
    } else {
      currentStep = DriverStep.online;
    }
    notifyListeners();
  }

  // 2. The NAHGM algorithm sends a ping
  void simulateIncomingRequest() {
    // Drivers can only receive requests if they are actively online and waiting
    if (currentStep == DriverStep.online) {
      currentRequest = MockRideRequest(
        id: "REQ-042",
        commuterName: "Sarah K.",
        commuterRating: 4.8,
        pickupNode: "Toril Node",
        dropoffNode: "Ulas Node",
        estimatedFare: 53.20,
        distance: "5.2 km",
      );
      currentStep = DriverStep.requestReceived;
      notifyListeners();
    }
  }

  // 3. Driver decisions
  void acceptRequest() {
    currentStep = DriverStep.headingToPickup;
    notifyListeners();
  }

  void declineRequest() {
    currentRequest = null;
    currentStep = DriverStep.online; // Drops them back to the active map
    notifyListeners();
  }

  // 4. Trip Execution
  void arriveAtPickup() {
    currentStep = DriverStep.arrivedAtPickup;
    notifyListeners();
  }

  void startRide() {
    currentStep = DriverStep.inRide;
    notifyListeners();
  }

  void completeRide() {
    currentStep = DriverStep.completed;
    notifyListeners();
  }

  // 5. Post-Trip Reset
  void resetToOnline() {
    currentRequest = null;
    currentStep = DriverStep.online;
    notifyListeners();
  }
}