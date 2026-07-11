import 'package:flutter/material.dart';
import '../../models/van_model.dart';
import '../../viewmodels/dispatcher/trip_schedule_viewmodel.dart';

class TripScheduleScreen extends StatefulWidget {
  const TripScheduleScreen({super.key});

  @override
  State<TripScheduleScreen> createState() => _TripScheduleScreenState();
}

class _TripScheduleScreenState extends State<TripScheduleScreen> {
  final TripScheduleViewModel _viewModel = TripScheduleViewModel();

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
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'Trip Schedules'),
                Tab(text: 'Manage Fleet'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSchedulesTab(),
                _buildFleetTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 1: Schedules ---
  Widget _buildSchedulesTab() {
    return Stack(
      children: [
        _viewModel.postedSchedules.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No upcoming schedules posted', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _viewModel.postedSchedules.length,
                itemBuilder: (context, index) {
                  // Schedule cards will go here
                  return const SizedBox.shrink(); 
                },
              ),
        
        // Post Schedule Button
        Positioned(
          bottom: 20,
          right: 20,
          left: 20,
          child: FilledButton.icon(
            onPressed: () {
              // TODO: Open "Post Schedule" Modal
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Post New Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  // --- Tab 2: Fleet Management ---
  Widget _buildFleetTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _viewModel.fleetVans.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final van = _viewModel.fleetVans[index];
        final isActive = van.status == VanStatus.active;
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_car, color: isActive ? const Color(0xFF2D2059) : Colors.grey),
                      const SizedBox(width: 12),
                      Text(van.plateNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive ? 'ACTIVE' : 'MAINTENANCE', 
                      style: TextStyle(color: isActive ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  const Icon(Icons.event_seat_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('${van.capacity} Seats Maximum', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.route_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'LTFRB Route Nodes: ${van.registeredRouteNodeIds.join(" <-> ")}', 
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}