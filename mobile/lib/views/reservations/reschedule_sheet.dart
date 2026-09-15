import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/trip_repository.dart';

/// Pick a new departure for an existing booking.
///
/// The journey is fixed — same boarding and alighting stops — because a
/// reschedule only moves the trip. Pops with the chosen trip id, or null.
class RescheduleSheet extends StatefulWidget {
  const RescheduleSheet({super.key, required this.booking, required this.trips});

  final BookingSummary booking;
  final TripRepository trips;

  @override
  State<RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<RescheduleSheet> {
  late DateTime _date;
  List<TripSummary> _options = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.booking.departure;
    final today = DateTime.now();
    _date = d.isBefore(today) ? DateTime(today.year, today.month, today.day) : DateTime(d.year, d.month, d.day);
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await widget.trips.searchSameRoute(
        routeId: widget.booking.routeId,
        boardingStop: widget.booking.boardingStop,
        alightingStop: widget.booking.alightingStop,
        serviceDate: _date,
      );
      _options = all
          .where((t) => t.tripId != widget.booking.tripId && !t.isFull && !t.hasDeparted)
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked == null) return;
    _date = picked;
    await _search();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Move to another departure',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 4),
            Text('${b.boardingTerminal} → ${b.alightingTerminal}',
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('EEE, MMM d').format(_date)),
            ),
            const SizedBox(height: 12),
            Flexible(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            TextButton(onPressed: _search, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No other departures with space on this day.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _options.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = _options[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.departure_board, color: AppColors.primary),
          title: Text(DateFormat('hh:mm a').format(t.departure),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            t.isNearlyFull ? '${t.spacesAvailable} spaces left' : '${t.spacesAvailable} spaces',
            style: TextStyle(color: t.isNearlyFull ? AppColors.warning : AppColors.textMuted),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, t.tripId),
        );
      },
    );
  }
}
