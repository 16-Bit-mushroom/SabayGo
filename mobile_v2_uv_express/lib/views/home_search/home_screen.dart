import 'package:flutter/material.dart';
import 'package:mobile_v2_uv_express/views/home_search/widgets/modern_route_card.dart';
import 'package:mobile_v2_uv_express/views/home_search/widgets/trip_details_sheet.dart';
import 'package:mobile_v2_uv_express/views/ticket/ticket_screen.dart';
import '../../viewmodels/home_search_viewmodel.dart';
import 'widgets/node_selector_field.dart';
import 'widgets/time_block_filter.dart';
import 'widgets/trip_card.dart';

/// Responsive breakpoint: below this, filters stack above the list.
/// At/above it, filters sit in a fixed side panel (tablet/web/desktop).
const double kWideLayoutBreakpoint = 700;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeSearchViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // Plain ChangeNotifier wiring — no external state package required.
    // Swap for Provider/Riverpod later if the app grows past one view.
    _viewModel = HomeSearchViewModel()..addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  // Update this function in home_screen.dart
  void _handleBook(String tripId) {
    final success = _viewModel.bookTrip(tripId);
    if (success) {
      // Find the trip data
      final bookedTrip = _viewModel.filteredTrips.firstWhere(
        (t) => t.id == tripId,
      );

      // Navigate to the Ticket Screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TicketScreen(bookedTrip: bookedTrip),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sorry, that trip is already full.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= kWideLayoutBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('UV Express'),
        actions: [
          IconButton(
            tooltip: 'Notification destinations',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _viewModel.refreshTrips,
          child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    return ModernRouteCard(
      origin: _viewModel.selectedOrigin,
      destination: _viewModel.selectedDestination,
      onOriginChanged:
          _viewModel.setOrigin, // Assuming these exist in viewmodel
      onDestinationChanged: _viewModel.setDestination,
    );
  }

  Widget _buildTripList() {
    final trips = _viewModel.filteredTrips;

    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (trips.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 48,
                    color: Theme.of(context).hintColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No trips match your filters',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        return InkWell(
          onTap: () {
            // Slide up the new details sheet!
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => TripDetailsSheet(
                trip: trip,
                onBook: () => _handleBook(trip.id),
              ),
            );
          },
          child: TripCard(
            trip: trip,
            onBook: () => {},
          ), // Keep your existing TripCard UI, just remove the book logic from the card itself
        );
      },
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildSearchPanel(),
        TimeBlockFilterBar(
          selected: _viewModel.selectedTimeBlock,
          onSelected: _viewModel.setTimeBlock,
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildTripList()),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: _buildSearchPanel()),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 12),
              TimeBlockFilterBar(
                selected: _viewModel.selectedTimeBlock,
                onSelected: _viewModel.setTimeBlock,
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildTripList()),
            ],
          ),
        ),
      ],
    );
  }
}
