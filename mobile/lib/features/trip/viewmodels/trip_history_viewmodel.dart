import 'package:flutter/material.dart';

// Domain Entity for a Trip
class Trip {
  final String id;
  final String origin;
  final String destination;
  final String price;
  final String date;
  final bool isEco;
  final bool isCompleted;
  final String driverName;
  final double driverRating;
  final String distance;
  final String duration;
  final String type;

  Trip({
    required this.id, required this.origin, required this.destination, 
    required this.price, required this.date, required this.isEco, 
    required this.isCompleted, required this.driverName, required this.driverRating,
    required this.distance, required this.duration, required this.type,
  });
}

class TripHistoryViewModel extends ChangeNotifier {
  bool isLoading = false;
  
  // UI State
  bool isFilterExpanded = false;
  String activeFilter = "All";
  String? expandedTripId;
  
  // Rating State Map<TripId, Value>
  Map<String, int> tripRatings = {};
  Map<String, bool> savedRatings = {};

  // Mock Data (To be replaced by Python Backend GET request)
  List<Trip> allTrips = [];

  TripHistoryViewModel() {
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));

    allTrips = [
      Trip(id: 'trip_1', origin: 'Matina Node', destination: 'SM City Ecoland', price: '₱165', date: 'Jun 11, 2026', isEco: true, isCompleted: true, driverName: 'Marcus W.', driverRating: 4.9, distance: '5.2 km', duration: '22 min', type: 'Shared'),
      Trip(id: 'trip_2', origin: 'Home', destination: 'Bangkal Hub', price: '₱120', date: 'Jun 10, 2026', isEco: false, isCompleted: true, driverName: 'Sarah K.', driverRating: 4.7, distance: '3.1 km', duration: '12 min', type: 'Solo'),
      Trip(id: 'trip_3', origin: 'Ulas', destination: 'Toril', price: '₱0', date: 'Jun 08, 2026', isEco: false, isCompleted: false, driverName: 'Unknown', driverRating: 0.0, distance: '-', duration: '-', type: 'Cancelled'),
    ];

    isLoading = false;
    notifyListeners();
  }

  // Getters for filtered data
  List<Trip> get filteredTrips {
    if (activeFilter == "All") return allTrips;
    if (activeFilter == "Completed") return allTrips.where((t) => t.isCompleted).toList();
    if (activeFilter == "Cancelled") return allTrips.where((t) => !t.isCompleted).toList();
    if (activeFilter == "Eco") return allTrips.where((t) => t.isEco).toList();
    if (activeFilter == "Solo") return allTrips.where((t) => t.type == "Solo").toList();
    return allTrips;
  }

  // UI Actions
  void toggleFilter() {
    isFilterExpanded = !isFilterExpanded;
    notifyListeners();
  }

  void setFilter(String filter) {
    activeFilter = filter;
    notifyListeners();
  }

  void toggleTripExpand(String tripId) {
    expandedTripId = expandedTripId == tripId ? null : tripId;
    notifyListeners();
  }

  // Rating Logic
  void rateTrip(String tripId, int rating) {
    tripRatings[tripId] = rating;
    notifyListeners();
  }

  void saveTripRating(String tripId) {
    savedRatings[tripId] = true;
    // Here you would trigger the POST request to your Python backend to save the rating
    notifyListeners();
  }

  void editTripRating(String tripId) {
    savedRatings[tripId] = false;
    notifyListeners();
  }
}