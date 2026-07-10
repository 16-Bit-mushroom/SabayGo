import 'package:flutter/foundation.dart';
import '../models/transit_node_model.dart';
import '../models/uv_trip_model.dart';

enum TimeBlock { all, nextAvailable, morning, afternoon, evening, lastTrip }

extension TimeBlockLabel on TimeBlock {
  String get label {
    switch (this) {
      case TimeBlock.all:
        return 'All';
      case TimeBlock.nextAvailable:
        return 'Next Available';
      case TimeBlock.morning:
        return 'Morning';
      case TimeBlock.afternoon:
        return 'Afternoon';
      case TimeBlock.evening:
        return 'Evening';
      case TimeBlock.lastTrip:
        return 'Last Trip';
    }
  }
}

class HomeSearchViewModel extends ChangeNotifier {
  HomeSearchViewModel() {
    _loadNodes();
    _loadTrips();
  }

  // --- State ---
  List<TransitNodeModel> _nodes = [];
  List<UvTripModel> _trips = [];

  TransitNodeModel? selectedOrigin;
  TransitNodeModel? selectedDestination;
  TimeBlock selectedTimeBlock = TimeBlock.all;
  String searchQuery = '';
  bool isLoading = false;

  List<TransitNodeModel> get nodes => _nodes;

  // --- Derived ---
  List<UvTripModel> get filteredTrips {
    final now = DateTime.now();
    var result = _trips.where((trip) {
      final matchesOrigin =
          selectedOrigin == null || trip.origin.id == selectedOrigin!.id;
      final matchesDestination = selectedDestination == null ||
          trip.destination.id == selectedDestination!.id;
      final query = searchQuery.toLowerCase();
      final matchesQuery = query.isEmpty ||
          trip.origin.name.toLowerCase().contains(query) ||
          trip.destination.name.toLowerCase().contains(query);
      return matchesOrigin && matchesDestination && matchesQuery;
    }).toList();

    switch (selectedTimeBlock) {
      case TimeBlock.all:
        break;
      case TimeBlock.nextAvailable:
        result = result.where((t) => t.departureTime.isAfter(now)).toList()
          ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
        if (result.length > 3) result = result.sublist(0, 3);
        break;
      case TimeBlock.morning:
        result = result
            .where((t) =>
                t.departureTime.hour >= 5 && t.departureTime.hour < 11)
            .toList();
        break;
      case TimeBlock.afternoon:
        result = result
            .where((t) =>
                t.departureTime.hour >= 11 && t.departureTime.hour < 15)
            .toList();
        break;
      case TimeBlock.evening:
        result = result
            .where((t) =>
                t.departureTime.hour >= 15 && t.departureTime.hour < 20)
            .toList();
        break;
      case TimeBlock.lastTrip:
        result = result.where((t) => t.isLastTrip).toList();
        break;
    }

    result.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return result;
  }

  // --- Actions ---
  void setOrigin(TransitNodeModel? node) {
    selectedOrigin = node;
    notifyListeners();
  }

  void setDestination(TransitNodeModel? node) {
    selectedDestination = node;
    notifyListeners();
  }

  void swapNodes() {
    final temp = selectedOrigin;
    selectedOrigin = selectedDestination;
    selectedDestination = temp;
    notifyListeners();
  }

  void setTimeBlock(TimeBlock block) {
    selectedTimeBlock = block;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  Future<void> refreshTrips() async {
    isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600)); // simulate fetch
    _loadTrips();
    isLoading = false;
    notifyListeners();
  }

  /// FR-6: one-tap seat reservation. Returns true if the lock succeeded.
  /// A real backend must guard this with a concurrency-safe transaction
  /// (e.g. row-level lock / atomic decrement) — this only mutates local
  /// state for the prototype.
  bool bookTrip(String tripId) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return false;
    final trip = _trips[index];
    if (trip.isFull) return false;

    final newAvailable = trip.availableSeats - 1;
    _trips[index] = trip.copyWith(
      availableSeats: newAvailable,
      status: newAvailable <= 0 ? TripStatus.full : trip.status,
    );
    notifyListeners();
    return true;
  }

  // --- Mock data (swap for a repository/API call later) ---
  void _loadNodes() {
    _nodes = const [
      TransitNodeModel(
          id: 'n1', name: 'UM Matina Gate', area: 'Matina, Davao City'),
      TransitNodeModel(
          id: 'n2', name: 'Bangkal Center', area: 'Bangkal, Davao City'),
      TransitNodeModel(id: 'n3', name: 'Ulas Hub', area: 'Ulas, Davao City'),
      TransitNodeModel(
          id: 'n4', name: 'Cotabato City Terminal', area: 'Cotabato City'),
      TransitNodeModel(
          id: 'n5', name: 'Toril Junction', area: 'Toril, Davao City'),
    ];
  }

  void _loadTrips() {
    final today = DateTime.now();
    DateTime at(int h, int m) =>
        DateTime(today.year, today.month, today.day, h, m);

    final davao = _nodes[0]; // UM Matina Gate
    final cotabato = _nodes[3]; // Cotabato City Terminal
    
    // Standard approx fare for this route
    const double standardFare = 150.0;
    // Standard travel time for this route
    const travelDuration = Duration(hours: 2);

    _trips = [
      UvTripModel(
        id: 't1',
        tripLabel: 'First Trip',
        departureTime: at(5, 30),
        estimatedArrivalTime: at(5, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 2,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
      ),
      UvTripModel(
        id: 't2',
        tripLabel: 'Second Trip',
        departureTime: at(7, 30),
        estimatedArrivalTime: at(7, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 11,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
      ),
      UvTripModel(
        id: 't3',
        tripLabel: 'Third Trip',
        departureTime: at(9, 30),
        estimatedArrivalTime: at(9, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 18,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
      ),
      UvTripModel(
        id: 't4',
        tripLabel: 'Fourth Trip',
        departureTime: at(11, 30),
        estimatedArrivalTime: at(11, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 4,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
      ),
      UvTripModel(
        id: 't5',
        tripLabel: 'Fifth Trip',
        departureTime: at(13, 30),
        estimatedArrivalTime: at(13, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 0,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
        status: TripStatus.full,
      ),
      UvTripModel(
        id: 't6',
        tripLabel: 'Sixth Trip',
        departureTime: at(15, 30),
        estimatedArrivalTime: at(15, 30).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 9,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
      ),
      UvTripModel(
        id: 't7',
        tripLabel: 'Last Trip',
        departureTime: at(18, 0),
        estimatedArrivalTime: at(18, 0).add(travelDuration), // ADDED
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 15,
        operatorName: 'RDT Transport',
        approximateFare: standardFare, // ADDED
        isLastTrip: true,
      ),
    ];
  }
}
