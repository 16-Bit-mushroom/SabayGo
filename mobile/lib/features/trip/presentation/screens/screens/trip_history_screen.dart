import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../../widgets/trip_summary_row.dart';
import '../../widgets/trip_filter_bar.dart';
import '../../widgets/trip_history_card.dart';

class TripHistoryScreen extends StatelessWidget {
  final bool isFilterExpanded;
  final VoidCallback onToggleFilter;
  final String activeFilter;
  final Function(String) onSelectFilter;
  
  // Trip State Management
  final String? expandedTripId;
  final Function(String) onToggleTripExpand;
  final Map<String, int> tripRatings;
  final Map<String, bool> savedRatings;
  final Function(String, int) onRateTrip;
  final Function(String) onSaveTripRating;
  final Function(String) onEditTripRating;

  const TripHistoryScreen({
    Key? key,
    required this.isFilterExpanded,
    required this.onToggleFilter,
    required this.activeFilter,
    required this.onSelectFilter,
    required this.expandedTripId,
    required this.onToggleTripExpand,
    required this.tripRatings,
    required this.savedRatings,
    required this.onRateTrip,
    required this.onSaveTripRating,
    required this.onEditTripRating,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Trip History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppColors.textPrimary)),
        automaticallyImplyLeading: false, // Hides back button for standard tab view
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          const TripSummaryRow(totalSpent: "₱940", totalSaved: "₱150", ecoRides: "3 trips"),
          const SizedBox(height: 24),
          TripFilterBar(
            isFilterExpanded: isFilterExpanded,
            onToggleFilter: onToggleFilter,
            activeFilter: activeFilter,
            onSelectFilter: onSelectFilter,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                TripHistoryCard(
                  origin: "Matina Node",
                  destination: "SM City Ecoland",
                  price: "₱165",
                  isExpanded: expandedTripId == 'trip_1',
                  onToggleExpand: () => onToggleTripExpand('trip_1'),
                  currentRating: tripRatings['trip_1'] ?? 0,
                  isRatingSaved: savedRatings['trip_1'] ?? false,
                  onRate: (rating) => onRateTrip('trip_1', rating),
                  onSaveRating: () => onSaveTripRating('trip_1'),
                  onEditRating: () => onEditTripRating('trip_1'),
                ),
                TripHistoryCard(
                  origin: "Home",
                  destination: "Bangkal Hub",
                  price: "₱120",
                  isEco: false,
                  isExpanded: expandedTripId == 'trip_2',
                  onToggleExpand: () => onToggleTripExpand('trip_2'),
                  currentRating: tripRatings['trip_2'] ?? 0,
                  isRatingSaved: savedRatings['trip_2'] ?? false,
                  onRate: (rating) => onRateTrip('trip_2', rating),
                  onSaveRating: () => onSaveTripRating('trip_2'),
                  onEditRating: () => onEditTripRating('trip_2'),
                ),
                TripHistoryCard(
                  origin: "Ulas",
                  destination: "Toril",
                  price: "₱0", // Cancelled
                  isCompleted: false,
                  isEco: false,
                  isExpanded: expandedTripId == 'trip_3',
                  onToggleExpand: () => onToggleTripExpand('trip_3'),
                  currentRating: tripRatings['trip_3'] ?? 0,
                  isRatingSaved: savedRatings['trip_3'] ?? false,
                  onRate: (rating) => onRateTrip('trip_3', rating),
                  onSaveRating: () => onSaveTripRating('trip_3'),
                  onEditRating: () => onEditTripRating('trip_3'),
                ),
              ],
            ),
          ),
        ],
      ),
      
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 1, // 'Trips' tab
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}