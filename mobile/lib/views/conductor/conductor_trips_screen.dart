import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// The trips this crew member is rostered to today.
///
/// A conductor is restricted server-side to trips they are assigned to,
/// so this list is also the boundary of what they can act on: tapping a
/// trip opens its manifest, and nothing outside the list is reachable.
///
/// Phase 3 replaces the placeholder state with a repository call to
/// GET /trips/assigned. The loading, empty and error states are built
/// now because retro-fitting them later means revisiting every screen.
class ConductorTripsScreen extends StatefulWidget {
  const ConductorTripsScreen({super.key});

  @override
  State<ConductorTripsScreen> createState() => _ConductorTripsScreenState();
}

class _ConductorTripsScreenState extends State<ConductorTripsScreen> {
  bool _loading = false;
  String? _error;
  final List<Object> _trips = const [];

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Phase 3: final trips = await context.read<TripRepository>().assigned();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Could not load your trips',
        body: _error!,
        action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
      );
    }

    if (_trips.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
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
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _trips.length,
        itemBuilder: (_, i) => const SizedBox.shrink(),
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