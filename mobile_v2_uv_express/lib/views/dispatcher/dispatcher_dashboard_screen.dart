import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/post_schedule_screen.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/trip_manifest_screen.dart';
import '../../models/uv_trip_model.dart';
import '../../viewmodels/dispatcher/dispatcher_dashboard_viewmodel.dart';

class DispatcherDashboardScreen extends StatefulWidget {
  const DispatcherDashboardScreen({super.key});

  @override
  State<DispatcherDashboardScreen> createState() =>
      _DispatcherDashboardScreenState();
}

class _DispatcherDashboardScreenState extends State<DispatcherDashboardScreen> {
  final DispatcherDashboardViewModel _viewModel =
      DispatcherDashboardViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              indicatorColor: const Color(0xFF00A859),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00A859),
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Active / Boarding'),
                Tab(text: 'Departed'),
              ],
            ),
          ),
          Expanded(
            child: _viewModel.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00A859)),
                  )
                : TabBarView(
                    children: [
                      // Active Tab (With Filter)
                      Column(
                        children: [
                          _buildFilterBar(),
                          Expanded(
                            child: _buildTripList(_viewModel.activeTrips),
                          ),
                        ],
                      ),
                      // Departed Tab (No Filter)
                      _buildTripList(
                        _viewModel.departedTrips,
                        isDeparted: true,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: DispatcherTimeBlock.values.map((block) {
            final isSelected = _viewModel.selectedBlock == block;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(block.label),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) _viewModel.setTimeBlock(block);
                },
                selectedColor: const Color(0xFF00A859).withOpacity(0.2),
                backgroundColor: Colors.grey.shade100,
                labelStyle: TextStyle(
                  color: isSelected
                      ? const Color(0xFF00A859)
                      : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTripList(List<UvTripModel> trips, {bool isDeparted = false}) {
    if (trips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car_filled_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isDeparted
                  ? 'No departed trips found'
                  : 'No active trips for this block',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00A859),
      onRefresh: () async => _viewModel.refreshDashboard(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: trips.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _DispatcherTripCard(trip: trips[index]);
        },
      ),
    );
  }
}

class _DispatcherTripCard extends StatelessWidget {
  final UvTripModel trip;

  const _DispatcherTripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final int occupiedSeats = trip.totalSeats - trip.availableSeats;
    final bool isFull = trip.availableSeats == 0;
    
    // Determine if the trip is still editable (usually only before departure)
    final bool isEditable = trip.status == TripStatus.scheduled || trip.status == TripStatus.boarding;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getStatusColor(trip.status).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusBadge(trip.status),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('hh:mm a').format(trip.departureTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.tripLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2D2059),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.trip_origin, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.origin.name,
                        style: TextStyle(color: Colors.grey.shade800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: Colors.grey,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        trip.destination.name,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Occupancy',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$occupiedSeats',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isFull
                                    ? Colors.red
                                    : const Color(0xFF00A859),
                              ),
                            ),
                            Text(
                              ' / ${trip.totalSeats} seats',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    // --- NEW: Action Buttons Row ---
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEditable) ...[
                          OutlinedButton(
                            onPressed: () {
                              // Link to the Post Schedule screen and pass the current trip
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PostScheduleScreen(existingTrip: trip),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade700),
                                const SizedBox(width: 4),
                                Text('Edit', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TripManifestScreen(trip: trip),
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2D2059),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: const Text(
                            'Manage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(TripStatus status) {
    switch (status) {
      case TripStatus.boarding:
        return const Color(0xFF00A859);
      case TripStatus.full:
        return Colors.orange;
      case TripStatus.departed:
        return Colors.grey;
      case TripStatus.cancelled:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _buildStatusBadge(TripStatus status) {
    String label = '';
    switch (status) {
      case TripStatus.scheduled:
        label = 'SCHEDULED';
        break;
      case TripStatus.boarding:
        label = 'BOARDING';
        break;
      case TripStatus.full:
        label = 'FULL';
        break;
      case TripStatus.departed:
        label = 'DEPARTED';
        break;
      case TripStatus.cancelled:
        label = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
