import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/pending_walk_in.dart';
import '../../core/offline/walk_in_sync_service.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../safety/sos_button.dart';
import 'qr_scanner_screen.dart';
import 'remittance_screen.dart';
import 'walk_in_screen.dart';

/// Who is booked on a trip and what has happened to them.
///
/// Everything shown comes from the server's manifest. The old version
/// kept its own passenger list and "simulated" scans by flipping a row;
/// now a scan, a walk-in or a departure changes the server and this
/// screen reloads to show the result.
class TripManifestScreen extends StatefulWidget {
  const TripManifestScreen({super.key, required this.trip});

  final CrewTrip trip;

  @override
  State<TripManifestScreen> createState() => _TripManifestScreenState();
}

class _TripManifestScreenState extends State<TripManifestScreen> {
  late final OperationsRepository _ops;
  Manifest? _manifest;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ops = OperationsRepository(context.read<ApiClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _manifest == null;
      _error = null;
    });
    try {
      final m = await _ops.manifest(widget.trip.tripId);
      if (!mounted) return;
      setState(() => _manifest = m);
      context.read<ShiftViewModel>().markStatus(m.status);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _acting = true);
    try {
      await action();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _push(Widget screen) async {
    final shift = context.read<ShiftViewModel>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: shift, child: screen),
      ),
    );
    _load();
  }

  Future<void> _startBoarding() => _act(() async {
        await _ops.startBoarding(widget.trip.tripId);
        await _load();
        _snack('Boarding open.');
      });

  Future<void> _depart() async {
    final m = _manifest;
    final awaiting = m == null ? 0 : m.awaiting + m.checkedIn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depart now?'),
        content: Text(
          awaiting > 0
              ? '$awaiting paid passenger${awaiting == 1 ? '' : 's'} ha${awaiting == 1 ? 's' : 've'} '
                  'not been scanned aboard. Departing marks them as no-shows and '
                  'releases their space. No refund is issued.'
              : 'Boarding will close. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Depart'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async {
      await _ops.depart(widget.trip.tripId);
      await _load();
      _snack('Trip departed.');
    });
  }

  Future<void> _headcount() async {
    final shift = context.read<ShiftViewModel>();
    final controller = TextEditingController();
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How many people are aboard?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Count everyone physically in the van at '
              '${widget.trip.stopName(shift.currentStop)}. The system compares '
              'this with the manifest and the camera.',
              style: const TextStyle(color: AppColors.textMuted, height: 1.3),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(hintText: '0'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (count == null) return;
    await _act(() async {
      final r = await _ops.headcount(
        tripId: widget.trip.tripId,
        stopSequence: shift.currentStop,
        confirmedCount: count,
      );
      _snack('${r.message} (counted ${r.confirmedCount}, manifest ${r.manifestCount})');
    });
  }

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<ShiftViewModel>();
    final trip = shift.active?.tripId == widget.trip.tripId ? shift.active! : widget.trip;
    final m = _manifest;
    final departed = trip.isDeparted;
    final sync = context.watch<WalkInSyncService>();
    final pending = sync.pendingFor(trip.tripId);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(trip.title, style: const TextStyle(fontSize: 18)),
        actions: [
          // Beside Refresh, not buried in the action list: hands are full
          // at the van door, and this is the one control that cannot be
          // hunted for.
          SosButton(tripId: trip.tripId),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && m == null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _statusPanel(trip, m!, shift),
                      if (pending.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _pendingSyncBanner(pending.length, sync),
                      ],
                      const SizedBox(height: 8),
                      _actions(trip, departed),
                      const SizedBox(height: 8),
                      _passengerList(trip, m, pending),
                    ],
                  ),
                ),
      floatingActionButton: departed || m == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _acting
                  ? null
                  : () => _push(QRScannerScreen(trip: trip, stopSequence: shift.currentStop)),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _statusPanel(CrewTrip trip, Manifest m, ShiftViewModel shift) {
    final (label, colour) = switch (m.status) {
      'boarding' => ('BOARDING', AppColors.accent),
      'departed' => ('DEPARTED', AppColors.textMuted),
      'completed' => ('COMPLETED', AppColors.textMuted),
      _ => ('SCHEDULED', AppColors.primary),
    };

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(color: colour, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM dd • hh:mm a').format(m.departure),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Boarded', m.boarded, AppColors.accent),
              _stat('Checked in', m.checkedIn, Colors.blue),
              _stat('Awaiting', m.awaiting, AppColors.warning),
              _stat('Unpaid', m.unpaid, AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Van is at', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: shift.currentStop,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    for (final s in trip.stops)
                      DropdownMenuItem(value: s.stopSequence, child: Text('${s.stopSequence}. ${s.terminalName}')),
                  ],
                  onChanged: trip.isDeparted ? null : (v) => v == null ? null : shift.setStop(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Cash the conductor has already collected but the server doesn't
  /// know about yet -- logged in a dead zone, waiting on the queue.
  /// Never hidden: a variance the office can't see coming is worse than
  /// one flagged in advance.
  Widget _pendingSyncBanner(int count, WalkInSyncService sync) => Container(
        color: AppColors.warning.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count passenger${count == 1 ? '' : 's'} logged offline, not yet synced.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: sync.flush, child: const Text('Sync now')),
          ],
        ),
      );

  Widget _stat(String label, int value, Color colour) => Expanded(
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colour)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _actions(CrewTrip trip, bool departed) {
    final buttons = <Widget>[
      if (trip.isScheduled)
        _actionButton(Icons.meeting_room, 'Open boarding', _startBoarding),
      if (!departed) ...[
        _actionButton(Icons.person_add, 'Walk-in', () => _push(WalkInScreen(trip: trip))),
        _actionButton(Icons.groups, 'Headcount', _headcount),
        _actionButton(Icons.logout, 'Depart', _depart, colour: AppColors.danger),
      ],
      if (departed) ...[
        _actionButton(Icons.person_add, 'Roadside', () => _push(WalkInScreen(trip: trip, roadside: true))),
        _actionButton(Icons.groups, 'Headcount', _headcount),
        _actionButton(Icons.payments, 'Remit cash', () => _push(RemittanceScreen(trip: trip))),
      ],
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, {Color? colour}) {
    return OutlinedButton.icon(
      onPressed: _acting ? null : onTap,
      icon: Icon(icon, size: 18, color: colour),
      label: Text(label, style: TextStyle(color: colour)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colour ?? const Color(0xFFDDDDE5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _passengerList(CrewTrip trip, Manifest m, List<PendingWalkIn> pending) {
    final visible = <ManifestPassenger>[
      ...m.passengers.where((p) => !p.isCancelled),
      for (final p in pending)
        ManifestPassenger.pendingSync(
          boardingStop: p.boardingStop,
          alightingStop: p.alightingStop,
          isRoadsidePickup: p.isRoadsidePickup,
          name: p.name,
        ),
    ]..sort((a, b) => a.boardingStop.compareTo(b.boardingStop));

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PASSENGER MANIFEST',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                Text('${m.totalBookings} booked · ${m.seatCapacity} spaces',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nobody booked yet.', style: TextStyle(color: AppColors.textMuted)),
            ),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _passengerTile(trip, visible[i]),
          ],
        ],
      ),
    );
  }

  Widget _passengerTile(CrewTrip trip, ManifestPassenger p) {
    final (label, colour) = switch (p.status) {
      'boarded' => ('BOARDED', AppColors.accent),
      'checked_in' => ('AT TERMINAL', Colors.blue),
      'confirmed' => ('NOT YET', AppColors.warning),
      'pending' => ('UNPAID', AppColors.textMuted),
      'no_show' => ('NO-SHOW', AppColors.danger),
      'pending_sync' => ('PENDING SYNC', AppColors.warning),
      _ => (p.status.toUpperCase(), AppColors.textMuted),
    };

    // How the passenger got on the manifest — booked ahead through the
    // app, paid cash at the terminal, or flagged the van down on the
    // road. A conductor scans a queue of strangers; this has to be
    // legible at a glance, not a suffix at the end of a grey line.
    final (methodLabel, methodColour, methodIcon) = switch (p) {
      _ when p.isRoadsidePickup => ('ROADSIDE', Colors.deepOrange, Icons.pan_tool_alt),
      _ when p.isWalkIn => ('TERMINAL CASH', Colors.teal, Icons.storefront),
      _ => ('APP BOOKING', AppColors.primary, Icons.smartphone),
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: methodColour.withValues(alpha: 0.12),
        child: Icon(methodIcon, color: methodColour, size: 20),
      ),
      title: Text(
        p.name ?? (p.isWalkIn ? 'Cash passenger' : 'App passenger'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: p.isNoShow ? Colors.grey : Colors.black87,
          decoration: p.isNoShow ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: methodColour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  methodLabel,
                  style: TextStyle(color: methodColour, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
              ),
              if (p.pickupLandmark != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.pickupLandmark!,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${p.ticketNumber} · ${trip.stopName(p.boardingStop)} → ${trip.stopName(p.alightingStop)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label, style: TextStyle(color: colour, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(
            p.isPendingSync
                ? '—'
                : '₱${p.fare.toStringAsFixed(0)}${p.fareIsManual ? '*' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
