import 'package:flutter/material.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/post_schedule_screen.dart';
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
    return Stack(
      children: [
        _viewModel.postedSchedules.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No upcoming schedules posted',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _viewModel.postedSchedules.length,
                itemBuilder: (context, index) {
                  return const SizedBox.shrink(); // Schedule cards go here
                },
              ),

        // Post Schedule Button
        Positioned(
          bottom: 20,
          right: 20,
          left: 20,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PostScheduleScreen()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text(
              'Post New Schedule',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
