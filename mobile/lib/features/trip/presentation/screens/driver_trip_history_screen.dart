import 'package:flutter/material.dart';
import 'package:mobile/features/trip/viewmodels/trip_history_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/trip_summary_row.dart';
import '../widgets/trip_filter_bar.dart';
import '../widgets/trip_history_card.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TripHistoryViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Trip History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppColors.textPrimary)),
        automaticallyImplyLeading: false, 
        elevation: 0,
        backgroundColor: AppColors.background,
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 16),
                // In a real app, these totals would also be calculated in the ViewModel
                const TripSummaryRow(totalSpent: "₱940", totalSaved: "₱150", ecoRides: "3 trips"),
                const SizedBox(height: 24),
                
                TripFilterBar(
                  isFilterExpanded: viewModel.isFilterExpanded,
                  onToggleFilter: () => viewModel.toggleFilter(),
                  activeFilter: viewModel.activeFilter,
                  onSelectFilter: (filter) => viewModel.setFilter(filter),
                ),
                const SizedBox(height: 16),
                
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: viewModel.filteredTrips.length,
                    itemBuilder: (context, index) {
                      final trip = viewModel.filteredTrips[index];
                      return TripHistoryCard(
                        origin: trip.origin,
                        destination: trip.destination,
                        price: trip.price,
                        isEco: trip.isEco,
                        isCompleted: trip.isCompleted,
                        isExpanded: viewModel.expandedTripId == trip.id,
                        onToggleExpand: () => viewModel.toggleTripExpand(trip.id),
                        currentRating: viewModel.tripRatings[trip.id] ?? 0,
                        isRatingSaved: viewModel.savedRatings[trip.id] ?? false,
                        onRate: (rating) => viewModel.rateTrip(trip.id, rating),
                        onSaveRating: () => viewModel.saveTripRating(trip.id),
                        onEditRating: () => viewModel.editTripRating(trip.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}