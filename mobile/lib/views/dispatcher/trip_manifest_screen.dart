import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/pending_walk_in.dart';
import '../../core/offline/walk_in_sync_service.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../safety/sos_button.dart';
import 'dashboard_panels.dart';
import 'qr_scanner_screen.dart';
import 'walk_in_screen.dart';

/// The Dispatcher's dashboard for one trip (rev 603, brief 9).
///
/// The passenger list with each destination and fare; the camera's count
/// aboard against the list, with a fix or a reason for each boarding not
/// on it; the crew toggle; Depart; 'Not a passenger trip'; home pickups;
/// A2Z's share to hand to the Cashier; and the operator, shown as a name
/// and licence beside the van's plate. It works before Start, from
/// assignment on. No van picking, no void or change-van: those are the
/// office's.
///
/// Everything shown comes from the server; an action changes the server
/// and the screen reloads to show the result.
class TripManifestScreen extends StatefulWidget {
  const TripManifestScreen({super.key, required this.trip});

  final CrewTrip trip;

  @override
  State<TripManifestScreen> createState() => _TripManifestScreenState();
}

class _TripManifestScreenState extends State<TripManifestScreen> {
  late final OperationsRepository _ops;
  Manifest? _manifest;
  DoorCheck? _check;
  TripShare? _share;
  Set<String> _disputedLines = const {};
  List<HomePickup> _pickups = const [];
  List<TripFlag> _flags = const [];
  NonPassengerMove? _move;
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
    final id = widget.trip.tripId;
    // Anything but the manifest may fail (offline, nothing yet) without
    // taking the screen down: that panel is simply left out.
    Future<Object?> optional(Future<Object?> call) => call.catchError((Object _) => null);
    try {
      final m = await _ops.manifest(id);
      final before = m.status == 'scheduled' || m.status == 'boarding';
      final results = await Future.wait<Object?>([
        before ? optional(_ops.doorCheck(id)) : Future.value(null),
        optional(_ops.share(id)),
        optional(_ops.disputedLines(id)),
        optional(_ops.homePickups(id)),
        before ? Future.value(null) : optional(_ops.flags(id)),
        optional(_ops.openMove()),
      ]);
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _check = results[0] as DoorCheck?;
        _share = results[1] as TripShare?;
        _disputedLines = results[2] as Set<String>? ?? const {};
        _pickups = results[3] as List<HomePickup>? ?? const [];
        _flags = [for (final f in results[4] as List<TripFlag>? ?? const <TripFlag>[]) if (f.flagged) f];
        _move = results[5] as NonPassengerMove?;
      });
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

  /// One call, then reload and say what happened.
  Future<void> _do(Future<void> Function() call, String done) => _act(() async {
        await call();
        await _load();
        _snack(done);
      });

  Future<String?> _ask(String title, String intro, String label, {bool required = true}) =>
      showDialog<String>(context: context, builder: (_) => _TextDialog(title, intro, label, required));

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      ) ==
      true;

  Future<void> _depart(CrewTrip trip) async {
    final unpaid = (_share?.amountDue ?? 0) > 0;
    final ok = await _confirm(
      'Depart now?',
      'Boarding closes and the passenger list locks. Paid passengers not aboard become no-shows; '
          'no refund is issued.${unpaid ? ' A2Z\'s share is not recorded yet: the van leaves unpaid '
              'and its next assignment waits until the Cashier records it.' : ''}',
      'Depart',
    );
    if (ok) await _do(() => _ops.depart(trip.tripId), 'Departed.');
  }

  Future<void> _explain(UnlistedBoarding u) async {
    final note = await _ask('Why is this person not on the list?',
        'For example: the operator\'s child, riding free to the next terminal. Kept with your name.', 'Reason');
    if (note != null) await _do(() => _ops.explain(u.eventId, note), 'Reason saved.');
  }

  Future<void> _notPassengerTrip() async {
    final picked = await showDialog<(String, String)>(context: context, builder: (_) => const _MoveDialog());
    if (picked != null) {
      await _do(() => _ops.startMove(picked.$1, note: picked.$2),
          'Not a passenger trip: nothing is started or owed until it ends.');
    }
  }

  Future<void> _pickup(HomePickup p, String action) async {
    switch (action) {
      case 'proof':
        await showDialog<void>(context: context, builder: (_) => _ProofDialog(load: () => _ops.pickupProof(p.pickupId)));
      case 'confirm':
        if (await _confirm('Confirm the payment?',
            'You checked the screenshot: the unpaid seats of this pickup are confirmed as paid through the app, '
                'with your name, and the Terminal Manager is told.', 'Confirm')) {
          await _do(() => _ops.confirmPickupProof(p.pickupId), 'Payment confirmed.');
        }
      case 'activate':
        await _do(() => _ops.activatePickup(p.pickupId), '${p.beneficiaryName}\'s pickup is activated.');
      case 'arrived':
        await _do(() => _ops.arrivedAtPickup(p.pickupId), 'At the pin. The wait is counted from now.');
      default:
        await _do(() => _ops.closePickup(p.pickupId, boarded: action == 'boarded'),
            action == 'boarded' ? '${p.beneficiaryName} is aboard.' : 'Recorded as a no-show. The seat is still owed.');
    }
  }

  Future<void> _dispute({ShareLine? line, TripFlag? flag}) async {
    final words = await _ask(
      'The operator\'s dispute',
      line != null
          ? '${line.count} × ₱${line.fare.toStringAsFixed(2)} to ${line.destination}. Its share waits until the '
              'Terminal Manager decides. A line can be disputed only until the payment is recorded.'
          : '${flag!.kind}. The Terminal Manager decides.',
      'The operator\'s words',
    );
    if (words != null) {
      await _do(() => _ops.dispute(lineId: line?.lineId, flagId: flag?.id, statement: words), 'Dispute recorded.');
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

  Future<void> _arrive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrived?'),
        content: const Text(
          'Tap this when the van is at its last stop and everyone is off. '
          'The trip will be completed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arrived')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async {
      await _ops.arrive(widget.trip.tripId);
      await _load();
      _snack('Trip completed.');
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
                      _statusPanel(trip, m!),
                      if (pending.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _pendingSyncBanner(pending.length, sync),
                      ],
                      if (_move case final move?) ...[
                        const SizedBox(height: 8),
                        _moveBanner(move),
                      ],
                      const SizedBox(height: 8),
                      _actions(trip, departed),
                      if (_check case final check? when trip.rental == null) ...[
                        const SizedBox(height: 8),
                        DoorCheckPanel(
                          check: check,
                          busy: _acting,
                          onList: (u) => _push(WalkInScreen(trip: trip, forEventId: u.eventId)),
                          onExplain: _explain,
                          onCrew: (v) => _do(() => _ops.setCrew(trip.tripId, v),
                              v ? 'You are marked crew: not counted.' : 'You are no longer marked crew.'),
                        ),
                      ],
                      if (_pickups.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        HomePickupsPanel(pickups: _pickups, departed: departed, busy: _acting, onAction: _pickup),
                      ],
                      if (trip.rental case final rental?) ...[
                        const SizedBox(height: 8),
                        RentalPanel(
                          rental: rental,
                          busy: _acting,
                          onCash: () => _do(() => _ops.rentalCash(rental.requestId), 'Rental fee recorded.'),
                        ),
                      ],
                      if (_share case final share? when share.lines.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SharePanel(
                          share: share,
                          disputedLines: _disputedLines,
                          busy: _acting,
                          onDispute: (l) => _dispute(line: l),
                        ),
                      ],
                      if (_flags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FlagsPanel(flags: _flags, busy: _acting, onDispute: (f) => _dispute(flag: f)),
                      ],
                      if (trip.rental == null) ...[
                        const SizedBox(height: 8),
                        _passengerList(trip, m, pending),
                      ],
                    ],
                  ),
                ),
      floatingActionButton: departed || m == null || trip.rental != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _acting
                  ? null
                  : () => _push(QRScannerScreen(trip: trip, stopSequence: trip.boardingStop)),
              backgroundColor: AppColors.success,
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

  Widget _statusPanel(CrewTrip trip, Manifest m) {
    final (label, tone) = switch (m.status) {
      'boarding' => ('STARTED', StatusTone.success),
      'departed' => ('DEPARTED', StatusTone.muted),
      'completed' => ('COMPLETED', StatusTone.muted),
      _ => ('SCHEDULED', StatusTone.brand),
    };

    return Container(
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(label, tone: tone),
              const Spacer(),
              Text(
                DateFormat('MMM dd • hh:mm a').format(m.departure),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The operator only as a name and licence, beside the plate
          // (brief 9): check the plate against the van at the door.
          Row(children: [
            const Icon(Icons.airport_shuttle_outlined, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${trip.plateNumber ?? 'No van yet'} · ${trip.operatorName ?? 'operator not known'}'
                '${trip.operatorLicence != null ? ', licence ${trip.operatorLicence}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          if (trip.rental == null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('Boarded', m.boarded, AppColors.success),
                _stat('Checked in', m.checkedIn, AppColors.info),
                _stat('Awaiting', m.awaiting, AppColors.warning),
                _stat('Unpaid', m.unpaid, AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Text('Everyone boards at ${trip.stopName(trip.boardingStop)}.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _moveBanner(NonPassengerMove move) => Container(
        color: AppColors.infoContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.no_transfer, size: 18, color: AppColors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Not a passenger trip (${_MoveDialog.words[move.reason] ?? move.reason}) since '
                '${DateFormat('h:mm a').format(move.startedAt)}. Ends by itself back at a terminal.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _acting ? null : () => _do(() => _ops.endMove(move.moveId), 'Not a passenger trip ended.'),
              child: const Text('End'),
            ),
          ],
        ),
      );

  /// Cash the Dispatcher has already collected but the server doesn't
  /// know about yet -- logged in a dead zone, waiting on the queue.
  /// Never hidden: a variance the office can't see coming is worse than
  /// one flagged in advance.
  Widget _pendingSyncBanner(int count, WalkInSyncService sync) => Container(
        color: AppColors.warningContainer,
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
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _actions(CrewTrip trip, bool departed) {
    // From assignment on the Dispatcher lists passengers, before the start
    // as well; the list closes at departure (rev 603, brief 2.4). Depart
    // is the Dispatcher's once the office has started the trip.
    final rental = trip.rental != null;
    final buttons = <Widget>[
      if (!departed && !rental)
        _actionButton(Icons.person_add, 'Walk-in', () => _push(WalkInScreen(trip: trip))),
      if (trip.isBoarding)
        _actionButton(Icons.logout, 'Depart', () => _depart(trip), colour: AppColors.primary),
      if (!departed && _move == null)
        _actionButton(Icons.no_transfer, 'Not a passenger trip', _notPassengerTrip),
      if (departed && !trip.isCompleted) _actionButton(Icons.flag, 'Arrived', _arrive),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

    // A two-column grid of equal 56dp targets rather than a wrap of
    // label-sized chips: every action is the same size and in the same
    // place trip after trip, so a hand can find it without a search
    // (Fitts's law; consistency). The old wrap reflowed with the labels.
    return Container(
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final b in buttons) SizedBox(width: w, child: b)],
        );
      }),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, {Color? colour}) {
    final c = colour ?? AppColors.textPrimary;
    return OutlinedButton.icon(
      onPressed: _acting ? null : onTap,
      icon: Icon(icon, size: 22, color: c),
      label: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        // Destructive actions (Depart) carry their colour on the outline
        // too; the rest use the 3:1 control border, not a hairline.
        side: BorderSide(color: colour ?? AppColors.border, width: colour != null ? 1.5 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
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
          name: p.name,
        ),
    ]..sort((a, b) => a.boardingStop.compareTo(b.boardingStop));

    return Container(
      color: AppColors.surfaceRaised,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PASSENGER MANIFEST',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.2)),
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
    final (label, tone) = switch (p.status) {
      'boarded' => ('BOARDED', StatusTone.success),
      'checked_in' => ('AT TERMINAL', StatusTone.info),
      'confirmed' => ('NOT YET', StatusTone.warning),
      'pending' => ('UNPAID', StatusTone.muted),
      'no_show' => ('NO-SHOW', StatusTone.danger),
      'pending_sync' => ('PENDING SYNC', StatusTone.info),
      _ => (p.status.toUpperCase(), StatusTone.muted),
    };

    // How the passenger got on the manifest — booked ahead through the
    // app or paid cash at a terminal. A Dispatcher scans a queue of
    // strangers; this has to be legible at a glance, not a suffix at the
    // end of a grey line.
    final (methodLabel, methodColour, methodIcon) = switch (p) {
      _ when p.isWalkIn => ('TERMINAL CASH', AppColors.success, Icons.storefront),
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
          color: p.isNoShow ? AppColors.textMuted : AppColors.textPrimary,
          decoration: p.isNoShow ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: methodColour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              methodLabel,
              style: TextStyle(color: methodColour, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${p.ticketNumber} · ${trip.stopName(p.boardingStop)} → ${trip.stopName(p.alightingStop)}',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(label, tone: tone),
          const SizedBox(height: 4),
          Text(
            p.isPendingSync
                ? '—'
                : '₱${p.fare.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}


/// A sentence: a reason, the operator's words. Null when cancelled.
class _TextDialog extends StatefulWidget {
  const _TextDialog(this.title, this.intro, this.label, this.required);
  final String title;
  final String intro;
  final String label;
  final bool required;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.intro),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 255,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.label),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: !widget.required || _text.text.trim().length >= 3
                ? () => Navigator.pop(context, _text.text.trim())
                : null,
            child: const Text('Save'),
          ),
        ],
      );
}

/// 'Not a passenger trip': pressed before leaving, with a reason (Table 40).
class _MoveDialog extends StatefulWidget {
  const _MoveDialog();

  static const words = {'errand': 'an errand', 'fuel_or_repair': 'fuel or repair', 'other': 'other'};

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String _reason = 'fuel_or_repair';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Not a passenger trip'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The van is leaving without passengers. Nothing is started or owed until you end it '
              'or the van is back at a terminal.'),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v!),
            child: Column(children: [
              for (final e in _MoveDialog.words.entries)
                RadioListTile(value: e.key, title: Text(e.value[0].toUpperCase() + e.value.substring(1))),
            ]),
          ),
          TextField(
            controller: _note,
            maxLength: 255,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: _reason == 'other' ? 'What for' : 'Note (optional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _reason != 'other' || _note.text.trim().isNotEmpty
                ? () => Navigator.pop(context, (_reason, _note.text.trim()))
                : null,
            child: const Text('Leave'),
          ),
        ],
      );
}

/// The relative's payment screenshot, for the Dispatcher to check.
class _ProofDialog extends StatelessWidget {
  const _ProofDialog({required this.load});
  final Future<Uint8List> Function() load;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Payment screenshot'),
        content: FutureBuilder<Uint8List>(
          future: load(),
          builder: (_, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return Text(e is ApiException ? e.message : 'The screenshot could not be loaded.');
            }
            if (!snap.hasData) {
              return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
            }
            return InteractiveViewer(child: Image.memory(snap.data!, fit: BoxFit.contain));
          },
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}
