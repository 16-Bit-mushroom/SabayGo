import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/trip_repository.dart';
import '../models/transit_node_model.dart';
import '../models/uv_trip_model.dart';

enum TimeBlock { all, nextAvailable, morning, afternoon, evening, lastTrip }

extension TimeBlockLabel on TimeBlock {
  String get label => switch (this) {
        // Sentence case, and "Any time" rather than "All": a filter row
        // reads as a question about this journey, not as a set of headings.
        TimeBlock.all => 'Any time',
        TimeBlock.nextAvailable => 'Leaving soon',
        TimeBlock.morning => 'Morning',
        TimeBlock.afternoon => 'Afternoon',
        TimeBlock.evening => 'Evening',
        TimeBlock.lastTrip => 'Last trip',
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

  /// The last journey searched, so a commuter who rides the same way every
  /// day opens the app on its departures with no taps (12 Nov). On the
  /// phone's secure store, like the session; a read that fails just means
  /// starting blank.
  static const _store = FlutterSecureStorage();
  static const _kOrigin = 'journey.origin';
  static const _kDestination = 'journey.destination';

  /// Each search's number: an answer to an older one, overtaken by a
  /// change of journey, is dropped rather than shown against the new one.
  int _searchSeq = 0;

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
  // Direction is the server's call: it knows which routes run origin ->
  // destination. The client only refuses the degenerate case.
  bool get canSearch =>
      selectedOrigin != null &&
      selectedDestination != null &&
      selectedOrigin!.id != selectedDestination!.id;

  /// Why the search button is disabled, phrased for the person rather
  /// than as a validation code.
  String? get searchBlockedReason {
    if (selectedOrigin == null) return 'Choose where you are boarding.';
    if (selectedDestination == null) return 'Choose where you are going.';
    if (selectedOrigin!.id == selectedDestination!.id) {
      return 'Boarding and destination are the same.';
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
      await _restoreJourney();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoadingTerminals = false;
      notifyListeners();
    }
    if (canSearch) search();
  }

  /// The journey to open on: the last one searched; otherwise "From" is
  /// the route's starting terminal when there is exactly one, because
  /// everyone boards there (rev 603) -- the passenger chooses only where
  /// they are going.
  Future<void> _restoreJourney() async {
    String? origin, destination;
    try {
      origin = await _store.read(key: _kOrigin);
      destination = await _store.read(key: _kDestination);
    } catch (_) {
      // No store (a test, a locked keystore): start blank.
    }
    TransitNodeModel? find(String? id) =>
        id == null ? null : _nodes.where((n) => n.id == id).firstOrNull;
    final starts = _nodes.where((n) => n.stopSequence == 1).toList();
    selectedOrigin ??= find(origin) ?? (starts.length == 1 ? starts.first : null);
    selectedDestination ??= find(destination);
  }

  Future<void> _rememberJourney() async {
    try {
      await _store.write(key: _kOrigin, value: selectedOrigin?.id);
      await _store.write(key: _kDestination, value: selectedDestination?.id);
    } catch (_) {
      // Remembering is a convenience; failing to is not an error to show.
    }
  }

  Future<void> search() async {
    if (!canSearch) return;
    final seq = ++_searchSeq;

    isLoadingTrips = true;
    error = null;
    notifyListeners();

    try {
      final results = await _repo.search(
        originTerminalId: selectedOrigin!.id,
        destinationTerminalId: selectedDestination!.id,
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
      if (seq != _searchSeq) return;
      _hasSearched = true;
    } on ApiException catch (e) {
      if (seq != _searchSeq) return;
      error = e.message;
      _trips = [];
    } finally {
      if (seq == _searchSeq) {
        isLoadingTrips = false;
        notifyListeners();
      }
    }
  }

  // Every change of journey searches at once (12 Nov): there is no
  // Search button to find and press, the departures simply follow the
  // choice.
  void setOrigin(TransitNodeModel? node) {
    selectedOrigin = node;
    _changed();
  }

  void setDestination(TransitNodeModel? node) {
    selectedDestination = node;
    _changed();
  }

  void swapNodes() {
    final temp = selectedOrigin;
    selectedOrigin = selectedDestination;
    selectedDestination = temp;
    _changed();
  }

  void setServiceDate(DateTime date) {
    serviceDate = date;
    _changed();
  }

  void _changed() {
    _invalidate();
    if (!canSearch) return;
    _rememberJourney();
    search();
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