import 'package:flutter/material.dart';
import '../../viewmodels/home_search_viewmodel.dart';
import 'widgets/where_to_card.dart';
import 'widgets/time_block_filter.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_details_sheet.dart';
import '../ticket/ticket_screen.dart';

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
    _viewModel = HomeSearchViewModel()..addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _handleBook(String tripId) {
    final success = _viewModel.bookTrip(tripId);
    if (success) {
      final bookedTrip = _viewModel.filteredTrips.firstWhere((t) => t.id == tripId);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => TicketScreen(bookedTrip: bookedTrip)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorry, that trip is already full.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= kWideLayoutBreakpoint;

    // REMOVED Scaffold AppBar here. The Parent handles it.
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _viewModel.refreshTrips,
        child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
      ),
    );
  }

  Widget _buildSearchPanel() {
    return WhereToCard(
      destination: _viewModel.selectedDestination,
      nodes: _viewModel.nodes,
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
                  Icon(Icons.event_busy, size: 48, color: Theme.of(context).hintColor),
                  const SizedBox(height: 8),
                  Text('No trips found for this destination.', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        return InkWell(
          onTap: () {
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
          child: TripCard(trip: trip), 
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