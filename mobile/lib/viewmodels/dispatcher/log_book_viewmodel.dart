import 'package:flutter/material.dart';
import '../../models/log_book_entry.dart';

class LogBookViewModel extends ChangeNotifier {
  LogBookViewModel() {
    _loadMockData();
  }

  List<LogBookEntry> allEntries = [];
  String activeFilter = 'All'; 
  String _searchQuery = ''; // --- NEW: Search Query State ---

  final List<String> availableFilters = [
    'All',
    'Trip Schedule',
    'Destination',
    'Date',
    'Van',
  ];

  void setFilter(String filter) {
    activeFilter = filter;
    notifyListeners();
  }

  // --- NEW: Search Action ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // --- UPDATED: Filtering Logic ---
  List<LogBookEntry> get filteredEntries {
    List<LogBookEntry> results = allEntries;

    // Apply Search Text Filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      results = results.where((entry) {
        return entry.passengerName.toLowerCase().contains(query) ||
               entry.contactNumber.toLowerCase().contains(query) ||
               entry.vanPlateNumber.toLowerCase().contains(query) ||
               entry.destinationName.toLowerCase().contains(query);
      }).toList();
    }

    // (Future) Apply advanced dropdown filtering based on activeFilter here
    return results; 
  }

  void _loadMockData() {
    final now = DateTime.now();
    allEntries = [
      LogBookEntry(
        id: 'L-001',
        passengerName: 'Sarah K. Dela Cruz',
        contactNumber: '+63 917 123 4567',
        address: 'Matina Crossing, Davao City',
        tripLabel: 'Van 2 - Plate XYZ-9876',
        destinationName: 'Cotabato City',
        vanPlateNumber: 'XYZ-9876',
        date: now,
      ),
      LogBookEntry(
        id: 'L-002',
        passengerName: 'Juan Miguel Santos',
        contactNumber: '+63 918 987 6543',
        address: 'Ecoland Drive, Davao City',
        tripLabel: 'Van 2 - Plate XYZ-9876',
        destinationName: 'Cotabato City',
        vanPlateNumber: 'XYZ-9876',
        date: now,
      ),
      LogBookEntry(
        id: 'L-003',
        passengerName: 'Maria Clara (Walk-in)',
        contactNumber: '09998887777',
        address: 'Buhangin, Davao City',
        tripLabel: 'Van 1 - Plate ABC-1234',
        destinationName: 'Tagum City',
        vanPlateNumber: 'ABC-1234',
        date: now.subtract(const Duration(hours: 3)),
      ),
    ];
    notifyListeners();
  }
}