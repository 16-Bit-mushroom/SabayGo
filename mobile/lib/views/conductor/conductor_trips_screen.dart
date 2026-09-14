import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/shift_viewmodel.dart';
import 'trip_manifest_screen.dart';

/// The trips this crew member is rostered to.
///
/// A conductor is restricted server-side to trips they are assigned to,
/// so this list is also the boundary of what they can act on: tapping a
/// trip opens its manifest, and nothing outside the list is reachable.
class ConductorTripsScreen extends StatefulWidget {
  const ConductorTripsScreen({super.key});

  @override
  State<ConductorTripsScreen> createState() => _ConductorTripsScreenState();
}

class _ConductorTripsScreenState extends State<ConductorTripsScreen> {
  @override
  void initState() {
    super.initState();
    // load() calls notifyListeners() before its first await (to flip on
    // the spinner), which the framework refuses mid-build — defer to
    // after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shift = context.read<ShiftViewModel>();
      if (!shift.hasLoaded) shift.load();
    });
  }

  void _open(CrewTrip trip) {
    final shift = context.read<ShiftViewModel>();
    shift.select(trip);
    // Pushed routes sit outside the shell's subtree, so the shift state
    // is carried across explicitly.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: shift,
          child: TripManifestScreen(trip: trip),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<ShiftViewModel>();

    if (shift.isLoading && !shift.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (shift.error != null && shift.trips.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Could not load your trips',
        body: shift.error!,
        action: FilledButton(onPressed: shift.load, child: const Text('Retry')),
      );
    }

    if (shift.trips.isEmpty) {
      return RefreshIndicator(
        onRefresh: shift.load,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            _Message(
              icon: Icons.event_busy_outlined,
              title: 'No trips assigned',
              body:
                  'You have no trips rostered right now. Pull down to refresh, '
                  'or ask the office if you expected one.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: shift.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: shift.trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _TripCard(
          trip: shift.trips[i],
          isActive: shift.active?.tripId == shift.trips[i].tripId,
          onTap: () => _open(shift.trips[i]),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.isActive, required this.onTap});

  final CrewTrip trip;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final first = trip.stops.isEmpty ? '' : trip.stops.first.terminalName;
    final last = trip.stops.isEmpty ? '' : trip.stops.last.terminalName;
    final (label, colour) = switch (trip.status) {
      'boarding' => ('BOARDING', AppColors.accent),
      'departed' => ('DEPARTED', AppColors.textMuted),
      'completed' => ('COMPLETED', AppColors.textMuted),
      _ => ('SCHEDULED', AppColors.primary),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? AppColors.accent : const Color(0xFFE6E6EE),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(label,
                        style: TextStyle(color: colour, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('$first → $last', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(DateFormat('EEE, MMM d • hh:mm a').format(trip.departure),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (trip.plateNumber != null) ...[
                    const Icon(Icons.directions_car, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(trip.plateNumber!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
