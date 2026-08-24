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
      TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City'),
      TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City'),
      TransitNodeModel(id: 'n3', name: 'Bulaong Terminal', area: 'General Santos City'),
      TransitNodeModel(id: 'n4', name: 'Agora Terminal', area: 'Cagayan de Oro City'),
      TransitNodeModel(id: 'n5', name: 'Tagum City Terminal', area: 'Tagum City'),
      TransitNodeModel(id: 'n6', name: 'Digos City Terminal', area: 'Digos City'),
    ];
  }

  void _loadTrips() {
    final today = DateTime.now();
    DateTime at(int h, int m) =>
        DateTime(today.year, today.month, today.day, h, m);

    // Fetch the loaded nodes
    final davao = _nodes.firstWhere((n) => n.id == 'n1');
    final cotabato = _nodes.firstWhere((n) => n.id == 'n2');
    final gensan = _nodes.firstWhere((n) => n.id == 'n3');
    final tagum = _nodes.firstWhere((n) => n.id == 'n5');

    _trips = [
      // --- DAVAO TO COTABATO ROUTES ---
      UvTripModel(
        id: 't1',
        tripLabel: 'First Trip',
        departureTime: at(5, 30),
        estimatedArrivalTime: at(5, 30).add(const Duration(hours: 5)),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 2,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
      ),
      UvTripModel(
        id: 't2',
        tripLabel: 'Second Trip',
        departureTime: at(7, 30),
        estimatedArrivalTime: at(7, 30).add(const Duration(hours: 5)),
        origin: davao,
        destination: cotabato,
        totalSeats: 18,
        availableSeats: 18,
        operatorName: 'RDT Transport',
        approximateFare: 500.0,
      ),
      
      // --- DAVAO TO GENSAN ROUTES ---
      UvTripModel(
        id: 't3',
        tripLabel: 'Morning Express',
        departureTime: at(8, 00),
        estimatedArrivalTime: at(8, 00).add(const Duration(hours: 3)),
        origin: davao,
        destination: gensan,
        totalSeats: 14,
        availableSeats: 0, // Mocking a full trip
        operatorName: 'Southbound Express',
        approximateFare: 350.0,
        status: TripStatus.full,
      ),
      UvTripModel(
        id: 't4',
        tripLabel: 'Noon Trip',
        departureTime: at(12, 00),
        estimatedArrivalTime: at(12, 00).add(const Duration(hours: 3)),
        origin: davao,
        destination: gensan,
        totalSeats: 14,
        availableSeats: 8,
        operatorName: 'Southbound Express',
        approximateFare: 350.0,
      ),

      // --- DAVAO TO TAGUM ROUTES (Shorter Trip) ---
      UvTripModel(
        id: 't5',
        tripLabel: 'Afternoon Run',
        departureTime: at(15, 30),
        estimatedArrivalTime: at(15, 30).add(const Duration(hours: 1, minutes: 30)),
        origin: davao,
        destination: tagum,
        totalSeats: 18,
        availableSeats: 12,
        operatorName: 'Metro Davao Vans',
        approximateFare: 150.0,
      ),
    ];
  }
}
