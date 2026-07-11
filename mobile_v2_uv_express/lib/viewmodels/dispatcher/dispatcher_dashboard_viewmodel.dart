import 'package:flutter/material.dart';
import '../../models/uv_trip_model.dart';
import '../../models/transit_node_model.dart';

enum DispatcherTimeBlock { all, morning, afternoon, evening }

extension DispatcherTimeBlockExt on DispatcherTimeBlock {
  String get label {
    switch (this) {
      case DispatcherTimeBlock.all: return 'All Trips';
      case DispatcherTimeBlock.morning: return 'Morning';
      case DispatcherTimeBlock.afternoon: return 'Afternoon';
      case DispatcherTimeBlock.evening: return 'Evening';
    }
  }
}

class DispatcherDashboardViewModel extends ChangeNotifier {
  DispatcherDashboardViewModel() {
    _loadOperatorTrips();
  }

  List<UvTripModel> todayTrips = [];
  bool isLoading = false;
  
  // --- Filter State ---
  DispatcherTimeBlock selectedBlock = DispatcherTimeBlock.all;

  void setTimeBlock(DispatcherTimeBlock block) {
    selectedBlock = block;
    notifyListeners();
  }

  // --- Derived State ---
  List<UvTripModel> get activeTrips {
    var trips = todayTrips
        .where((t) => t.status == TripStatus.scheduled || t.status == TripStatus.boarding || t.status == TripStatus.full)
        .toList();

    switch (selectedBlock) {
      case DispatcherTimeBlock.all:
        break;
      case DispatcherTimeBlock.morning:
        trips = trips.where((t) => t.departureTime.hour >= 0 && t.departureTime.hour < 12).toList();
        break;
      case DispatcherTimeBlock.afternoon:
        trips = trips.where((t) => t.departureTime.hour >= 12 && t.departureTime.hour < 17).toList();
        break;
      case DispatcherTimeBlock.evening:
        trips = trips.where((t) => t.departureTime.hour >= 17).toList();
        break;
    }

    // Sort chronologically
    trips.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return trips;
  }

  List<UvTripModel> get departedTrips {
    var trips = todayTrips.where((t) => t.status == TripStatus.departed).toList();
    trips.sort((a, b) => b.departureTime.compareTo(a.departureTime)); // Newest departures first
    return trips;
  }

  // --- Actions ---
  void refreshDashboard() async {
    isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 800));
    _loadOperatorTrips();
    isLoading = false;
    notifyListeners();
  }

  void _loadOperatorTrips() {
    final today = DateTime.now();
    DateTime at(int h, int m) => DateTime(today.year, today.month, today.day, h, m);

    const davao = TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City');
    const cotabato = TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City');

    todayTrips = [
      UvTripModel(
        id: 't1',
        tripLabel: 'Van 1 - Plate ABC-1234',
        departureTime: at(8, 0),
        estimatedArrivalTime: at(13, 0),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 0,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
        status: TripStatus.departed,
      ),
      UvTripModel(
        id: 't2',
        tripLabel: 'Van 2 - Plate XYZ-9876',
        departureTime: at(11, 30),
        estimatedArrivalTime: at(16, 30),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 2,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
        status: TripStatus.boarding,
      ),
      UvTripModel(
        id: 't3',
        tripLabel: 'Van 3 - Unassigned',
        departureTime: at(15, 0), // Afternoon
        estimatedArrivalTime: at(20, 0),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 18,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
        status: TripStatus.scheduled,
      ),
      UvTripModel(
        id: 't4',
        tripLabel: 'Van 4 - Night Rider',
        departureTime: at(18, 30), // Evening
        estimatedArrivalTime: at(23, 30),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 10,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
        status: TripStatus.scheduled,
      ),
    ];
    notifyListeners();
  }
}