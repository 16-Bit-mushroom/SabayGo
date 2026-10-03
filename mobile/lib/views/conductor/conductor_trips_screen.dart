import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
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
    final (label, tone) = switch (trip.status) {
      'boarding' => ('BOARDING', StatusTone.success),
      'departed' => ('DEPARTED', StatusTone.muted),
      'completed' => ('COMPLETED', StatusTone.muted),
      _ => ('SCHEDULED', StatusTone.brand),
    };

    // Ordered by what a crew member checks first: *when* (the time, set
    // large enough to read at arm's length in sun), then *where*, then
    // *which van*. The time used to be a 14px line at the bottom of the
    // card, below the route -- the question asked most was answered last.
    return Semantics(
      button: true,
      label: '${trip.title}, ${DateFormat('EEEE h:mm a').format(trip.departure)}, '
          '${label.toLowerCase()}${trip.plateNumber != null ? ', van ${trip.plateNumber}' : ''}',
      // excludeSemantics drops the InkWell's own tap action along with its
      // labels, so the tap must be restated here -- without it a screen
      // reader announced the trip but could not open it.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              // The trip in hand is outlined in ink at 2px -- a change of
              // weight, not only of hue, so it reads on a washed-out screen.
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.divider,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('h:mm a').format(trip.departure),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            DateFormat('EEE, MMM d').format(trip.departure),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(label, tone: tone),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  trip.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                ),
                if (first.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('$first → $last',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                ],
                if (trip.plateNumber != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(Icons.airport_shuttle_outlined, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(trip.plateNumber!,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                ],
              ],
            ),
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
