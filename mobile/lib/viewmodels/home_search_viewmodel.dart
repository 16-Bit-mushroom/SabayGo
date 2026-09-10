import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/trip_repository.dart';
import '../models/transit_node_model.dart';
import '../models/uv_trip_model.dart';

enum TimeBlock { all, nextAvailable, morning, afternoon, evening, lastTrip }

extension TimeBlockLabel on TimeBlock {
  String get label => switch (this) {
        TimeBlock.all => 'All',
        TimeBlock.nextAvailable => 'Next Available',
        TimeBlock.morning => 'Morning',
        TimeBlock.afternoon => 'Afternoon',
        TimeBlock.evening => 'Evening',
        TimeBlock.lastTrip => 'Last Trip',
      };
}

/// Trip search, backed by the API.
///
/// The important change from the prototype: **search is segment-based**.
/// The old version loaded every trip and filtered client-side, so the
/// list showed something immediately. The server cannot work that way —
/// a trip has no single fare or availability until the journey is known,
/// because both are properties of the sections of road travelled.
/// Ecoland→Digos and Ecoland→Cotabato are different prices on the same
/// van, and can have different space.
///
/// So nothing lists until both terminals are chosen. That is the segment
/// model showing through, not a limitation to design around.
class HomeSearchViewModel extends ChangeNotifier {
  HomeSearchViewModel(this._repo) {
    loadTerminals();
  }

  final TripRepository _repo;

  // --- state ---
  List<TransitNodeModel> _nodes = [];
  List<UvTripModel> _trips = [];

  TransitNodeModel? selectedOrigin;
  TransitNodeModel? selectedDestination;
  DateTime serviceDate = DateTime.now();
  TimeBlock selectedTimeBlock = TimeBlock.all;
  String searchQuery = '';

  bool isLoadingTerminals = false;
  bool isLoadingTrips = false;
  String? error;

  /// True before the first search — the list is empty because nothing
  /// has been asked for yet, which is a different state from a search
  /// that found nothing.
  bool _hasSearched = false;

  List<TransitNodeModel> get nodes => _nodes;
  bool get hasSearched => _hasSearched;
  bool get canSearch =>
      selectedOrigin?.stopSequence != null &&
      selectedDestination?.stopSequence != null &&
      selectedOrigin!.stopSequence! < selectedDestination!.stopSequence!;

  /// Why the search button is disabled, phrased for the person rather
  /// than as a validation code.
  String? get searchBlockedReason {
    if (selectedOrigin == null) return 'Choose where you are boarding.';
    if (selectedDestination == null) return 'Choose where you are going.';
    final from = selectedOrigin!.stopSequence;
    final to = selectedDestination!.stopSequence;
    if (from == null || to == null) return 'This terminal is not on a route.';
    if (from == to) return 'Boarding and destination are the same.';
    if (from > to) {
      return 'This route runs ${_nodes.first.name} outward. '
          'Swap your terminals to travel the other way.';
    }
    return null;
  }

  // --- derived ---
  List<UvTripModel> get filteredTrips {
    final now = DateTime.now();
    final query = searchQuery.toLowerCase();

    var result = _trips.where((t) {
      if (query.isEmpty) return true;
      return t.origin.name.toLowerCase().contains(query) ||
          t.destination.name.toLowerCase().contains(query) ||
          t.tripLabel.toLowerCase().contains(query);
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
            .where((t) => t.departureTime.hour >= 5 && t.departureTime.hour < 11)
            .toList();
        break;
      case TimeBlock.afternoon:
        result = result
            .where((t) => t.departureTime.hour >= 11 && t.departureTime.hour < 15)
            .toList();
        break;
      case TimeBlock.evening:
        result = result
            .where((t) => t.departureTime.hour >= 15 && t.departureTime.hour < 20)
            .toList();
        break;
      case TimeBlock.lastTrip:
        // The last departure of the day for this journey, rather than a
        // flag the server sends — it is a property of the result set.
        if (result.isNotEmpty) {
          result.sort((a, b) => a.departureTime.compareTo(b.departureTime));
          result = [result.last];
        }
        break;
    }

    result.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return result;
  }

  // --- actions ---
  Future<void> loadTerminals() async {
    isLoadingTerminals = true;
    error = null;
    notifyListeners();
    try {
      final terminals = await _repo.terminals();
      _nodes = terminals
          .map((t) => TransitNodeModel(
                id: t.terminalId,
                name: t.terminalName,
                area: t.city,
                stopSequence: t.stopSequence,
              ))
          .toList();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoadingTerminals = false;
      notifyListeners();
    }
  }

  Future<void> search() async {
    if (!canSearch) return;

    isLoadingTrips = true;
    error = null;
    notifyListeners();

    try {
      final results = await _repo.search(
        boardingStop: selectedOrigin!.stopSequence!,
        alightingStop: selectedDestination!.stopSequence!,
        serviceDate: serviceDate,
      );
      // Names come back scoped to the searched journey, so the terminals
      // the passenger picked are carried through rather than re-derived.
      _trips = results
          .map((t) => UvTripModel(
                id: t.tripId,
                tripLabel: t.tripLabel ?? t.routeName,
                departureTime: t.departure,
                origin: selectedOrigin!,
                destination: selectedDestination!,
                boardingStop: t.boardingStop,
                alightingStop: t.alightingStop,
                availableSeats: t.spacesAvailable,
                approximateFare: t.fare,
                plateNumber: t.plateNumber,
                isSpecialTrip: t.isSpecialTrip,
                status: t.isFull ? TripStatus.full : TripStatus.scheduled,
              ))
          .toList();
      _hasSearched = true;
    } on ApiException catch (e) {
      error = e.message;
      _trips = [];
    } finally {
      isLoadingTrips = false;
      notifyListeners();
    }
  }

  void setOrigin(TransitNodeModel? node) {
    selectedOrigin = node;
    _invalidate();
  }

  void setDestination(TransitNodeModel? node) {
    selectedDestination = node;
    _invalidate();
  }

  void swapNodes() {
    final temp = selectedOrigin;
    selectedOrigin = selectedDestination;
    selectedDestination = temp;
    _invalidate();
  }

  void setServiceDate(DateTime date) {
    serviceDate = date;
    _invalidate();
  }

  void setTimeBlock(TimeBlock block) {
    selectedTimeBlock = block;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  Future<void> refreshTrips() => search();

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  /// Changing the journey invalidates the results, because fare and
  /// availability were computed for the previous one. Showing stale
  /// prices against a new destination would be worse than showing none.
  void _invalidate() {
    _trips = [];
    _hasSearched = false;
    notifyListeners();
  }
}