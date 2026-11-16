import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/pending_walk_in.dart';
import '../../core/offline/seat_mark_queue.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../safety/sos_button.dart';
import 'dashboard_panels.dart';
import 'walk_in_screen.dart';

/// The Dispatcher's dashboard for one trip (rev 603, brief 9; rev 721).
///
/// The reservations, found by name or booking code, each marked Paid when
/// the passenger hands over the cash or cancelled -- both work offline and
/// sync on reconnect; the passenger list with each destination and fare;
/// the camera's count
/// aboard against the list, with a fix or a reason for each boarding not
/// on it; the crew toggle; Depart; 'Not a passenger trip'; home pickups;
/// the terminal fees to hand to the Cashier; and the operator, shown as a name
/// and licence beside the van's plate. It works before Start, from
/// assignment on. No van picking, no void or change-van: those are the
/// office's.
///
/// Everything shown comes from the server; an action changes the server
/// and the screen reloads to show the result. The reservations list is
/// kept from the last load, so a dead zone does not take it away.
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
  /// The trip's reservations and walk-ins, as last loaded. Searched on
  /// the device, so a name or code can be found without a connection.
  List<SeatOnList>? _seats;
  final _search = TextEditingController();

  /// Which reservations show: those still to collect, the paid, or all.
  /// Until the Dispatcher picks, it follows the work: "To collect" while
  /// anyone is unpaid, else everyone.
  _Show _show = _Show.auto;
  late final OfflineSyncService _sync;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ops = OperationsRepository(context.read<ApiClient>());
    _sync = context.read<OfflineSyncService>()..addListener(_showSyncNotices);
    _load();
  }

  @override
  void dispose() {
    _sync.removeListener(_showSyncNotices);
    _search.dispose();
    super.dispose();
  }

  /// A mark that synced later may come back restored, with no seat left,
  /// or refused: the Dispatcher has to hear about each.
  void _showSyncNotices() {
    final notices = _sync.takeNotices();
    if (notices.isEmpty || !mounted) return;
    for (final n in notices) {
      _snack(n);
    }
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
        before ? optional(_ops.seats(id)) : Future.value(null),
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
        // Keep the last list when this load could not fetch it (offline).
        if (results[6] case final List<SeatOnList> seats) _seats = seats;
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

  /// The passenger handed over the fare in cash.
  Future<void> _markPaid(SeatOnList s) async {
    final who = s.passengerName ?? s.bookingCode;
    if (!await _confirm('Mark as Paid?',
        '$who · ${s.bookingCode}\n₱${s.fare.toStringAsFixed(2)} in cash, in your hand now.', 'Mark as Paid')) {
      return;
    }
    await _act(() async {
      final r = await _sync.markPaidOrQueue(tripId: widget.trip.tripId, bookingId: s.bookingId, label: who);
      if (r.queued) {
        _snack('No connection: $who is marked Paid on this phone and syncs when you are back online.');
      } else {
        _snack(r.notice ?? '$who is Paid and on the passenger list.');
        await _load();
      }
    });
  }

  /// The passenger asked to cancel (any cash is handed back), or nobody
  /// came for an unpaid reservation.
  Future<void> _cancelSeat(SeatOnList s) async {
    final who = s.passengerName ?? s.bookingCode;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Cancel $who\'s reservation?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'passenger_asked_dispatcher'),
            child: Text(s.isPaid
                ? 'The passenger asked. I hand back the ₱${s.fare.toStringAsFixed(2)} I took.'
                : 'The passenger asked me to cancel it.'),
          ),
          if (!s.isPaid)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'forgot_to_cancel'),
              child: const Text('Nobody came for it.'),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: const Text('Keep it')),
        ],
      ),
    );
    if (reason == null) return;
    await _act(() async {
      final r = await _sync.cancelOrQueue(
          tripId: widget.trip.tripId, bookingId: s.bookingId, label: who, reason: reason);
      if (r.queued) {
        _snack('No connection: the cancel is saved on this phone and syncs when you are back online.');
      } else {
        _snack('$who\'s reservation is cancelled and the seat is free.');
        await _load();
      }
    });
  }

  Future<void> _pickup(HomePickup p, String action) async {
    switch (action) {
      case 'photo':
        await showDialog<void>(context: context, builder: (_) => _PhotoDialog(load: () => _ops.pickupPhoto(p.pickupId)));
      case 'activate':
        await _do(() => _ops.activatePickup(p.pickupId), '${p.beneficiaryName}\'s pickup is activated.');
      case 'arrived':
        await _do(() => _ops.arrivedAtPickup(p.pickupId), 'At the pin. The wait is counted from now.');
      default:
        await _do(() => _ops.closePickup(p.pickupId, boarded: action == 'boarded'),
            action == 'boarded' ? '${p.beneficiaryName} is aboard.' : 'Recorded as a no-show. The fare is still due.');
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
    final sync = context.watch<OfflineSyncService>();
    final pending = sync.pendingFor(trip.tripId);
    final marks = sync.marksFor(trip.tripId);

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
          // The rare action lives here, not beside Depart: a choice made a
          // few times a month should not cost a look every trip (Hick).
          if (!departed && _move == null)
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_acting,
              onSelected: (_) => _notPassengerTrip(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                    leading: Icon(Icons.no_transfer),
                    title: Text('Not a passenger trip'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      // The trip's next action sits at the bottom, under the thumb, and
      // stays there while the list scrolls (Fitts).
      bottomNavigationBar: _loading || m == null ? null : _actionBar(trip, departed),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && m == null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    // In the order of the work: where the trip stands and what
                    // to do next; anything that blocks Depart; the list the
                    // Dispatcher works through; then the money and the rest.
                    children: [
                      _statusPanel(trip, m!, marks),
                      if (pending.isNotEmpty || marks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _pendingSyncBanner(pending.length, marks.length, sync),
                      ],
                      if (_move case final move?) ...[
                        const SizedBox(height: 8),
                        _moveBanner(move),
                      ],
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
                      if (trip.rental == null && !departed) ...[
                        const SizedBox(height: 8),
                        _reservations(trip, marks),
                      ],
                      if (trip.rental == null && departed) ...[
                        const SizedBox(height: 8),
                        _passengerList(trip, m, pending),
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
                      if (_share case final share? when share.lines.isNotEmpty || share.amountDue > 0) ...[
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
                    ],
                  ),
                ),
    );
  }

  /// Every reservation and walk-in, found by name or code, filtered to
  /// what is still to collect, what is paid, or all. A mark still on the
  /// phone shows as such until it syncs.
  Widget _reservations(CrewTrip trip, Map<String, PendingSeatMark> marks) {
    final all = (all: _seats ?? const <SeatOnList>[], loaded: _seats != null);
    final live = [for (final s in all.all) if (marks[s.bookingId]?.kind != 'cancel') s];
    bool owing(SeatOnList s) => !s.isPaid && !(marks[s.bookingId]?.isPaid ?? false);
    // Whoever pressed "I'm here to pay" is at the terminal with cash: first.
    final toCollect = live.where(owing).toList()
      ..sort((a, b) => (b.status == 'checked_in' ? 1 : 0) - (a.status == 'checked_in' ? 1 : 0));
    final paid = live.where((s) => !owing(s)).toList();
    final show = _show == _Show.auto ? (toCollect.isEmpty ? _Show.all : _Show.collect) : _show;
    final q = _search.text.trim().toLowerCase();
    final base = switch (show) {
      _Show.collect => toCollect,
      _Show.paid => paid,
      _ => [...toCollect, ...paid],
    };
    final shown = [
      for (final s in base)
        if (q.isEmpty ||
            s.bookingCode.toLowerCase().contains(q) ||
            (s.passengerName ?? '').toLowerCase().contains(q))
          s,
    ];

    Widget chip(_Show value, String label, int count) => ChoiceChip(
          label: Text('$label  $count'),
          selected: show == value,
          showCheckmark: false,
          onSelected: (_) => setState(() => _show = value),
        );

    return Container(
      color: AppColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text('RESERVATIONS AND WALK-INS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.2)),
          ),
          if (all.loaded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                chip(_Show.collect, 'To collect', toCollect.length),
                chip(_Show.paid, 'Paid', paid.length),
                chip(_Show.all, 'All', live.length),
              ]),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Booking code or name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!all.loaded)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('The list has not loaded. Pull down to try again.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  q.isNotEmpty
                      ? 'No reservation matches "${_search.text.trim()}".'
                      : switch (show) {
                          _Show.collect => 'Nobody left to collect from. Everyone listed has paid.',
                          _Show.paid => 'Nobody has paid yet.',
                          _ => 'Nobody has reserved yet. Add walk-ins with the button below.',
                        },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _seatTile(trip, shown[i], marks[shown[i].bookingId]),
          ],
        ],
      ),
    );
  }

  /// One passenger, read in the order the Dispatcher checks it at the
  /// door: who, the code they show, where they get off and the fare; then
  /// the one action, on its own line so it never squeezes the name, with
  /// the amount on it -- the cash to take is on the button that records it.
  Widget _seatTile(CrewTrip trip, SeatOnList s, PendingSeatMark? mark) {
    final paidHere = mark?.isPaid ?? false;
    final paid = s.isPaid || paidHere;
    final (label, tone) = switch (s.status) {
      _ when paidHere => ('PAID · NOT SYNCED', StatusTone.info),
      'boarded' => ('ABOARD', StatusTone.success),
      _ when paid => ('PAID', StatusTone.success),
      // Pressed "I'm here to pay": at the terminal, cash in hand.
      'checked_in' => ('HERE TO PAY', StatusTone.info),
      _ => ('UNPAID', StatusTone.warning),
    };
    final who = s.passengerName ?? (s.isWalkIn ? 'Walk-in passenger' : 'App passenger');
    final canCancel = mark == null && !s.isWalkIn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(who, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(label, tone: tone),
            const SizedBox(width: AppSpacing.sm),
          ]),
          const SizedBox(height: 4),
          Text(s.bookingCode,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(
            'To ${trip.stopName(s.alightingStop)} · ₱${s.fare.toStringAsFixed(0)}'
            '${s.isWalkIn ? ' · walk-in' : ''}${s.isHomePickupSeat ? ' · home pickup' : ''}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          if (!paid || canCancel) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              if (canCancel)
                TextButton(
                  onPressed: _acting ? null : () => _cancelSeat(s),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(0, AppSizing.minTouchTarget),
                  ),
                  child: const Text('Cancel'),
                ),
              const Spacer(),
              if (!paid)
                FilledButton.icon(
                  // The theme's buttons are full width; here it sizes to
                  // its label at the end of its own line.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                  onPressed: _acting ? null : () => _markPaid(s),
                  icon: const Icon(Icons.payments_outlined, size: 20),
                  label: Text('Mark ₱${s.fare.toStringAsFixed(0)} paid'),
                ),
            ]),
          ],
        ],
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

  Widget _statusPanel(CrewTrip trip, Manifest m, Map<String, PendingSeatMark> marks) {
    final (label, tone) = switch (m.status) {
      'boarding' => ('STARTED', StatusTone.success),
      'departed' => ('ON THE ROAD', StatusTone.muted),
      'completed' => ('COMPLETED', StatusTone.muted),
      _ => ('SCHEDULED', StatusTone.brand),
    };
    final taken = m.totalBookings.clamp(0, m.seatCapacity);

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
                DateFormat('EEE d MMM · h:mm a').format(m.departure),
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
                _stat('Paid', m.totalBookings - m.unpaid, AppColors.success),
                _stat('Unpaid', m.unpaid, AppColors.warning),
                _stat('At terminal', m.checkedIn, AppColors.info),
                _stat('Seats left', (m.seatCapacity - m.totalBookings).clamp(0, m.seatCapacity), AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            // How full the van is, at a glance: listed of its spaces.
            Semantics(
              label: '$taken of ${m.seatCapacity} seats taken',
              excludeSemantics: true,
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: LinearProgressIndicator(
                      value: m.seatCapacity == 0 ? 0 : taken / m.seatCapacity,
                      minHeight: 8,
                      backgroundColor: AppColors.primaryContainer,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text('$taken of ${m.seatCapacity}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 16),
            _nextStep(trip, marks),
          ],
        ],
      ),
    );
  }

  /// What to do now, in one sentence, from the trip's state: the
  /// Dispatcher never has to work out which button applies.
  Widget _nextStep(CrewTrip trip, Map<String, PendingSeatMark> marks) {
    final owing = [
      for (final s in _seats ?? const <SeatOnList>[])
        if (!s.isPaid && marks[s.bookingId] == null) s,
    ];
    final cash = owing.fold<double>(0, (sum, s) => sum + s.fare);
    final here = owing.where((s) => s.status == 'checked_in').length;
    final blocked = (_check?.excess ?? 0) > 0;
    final last = trip.stops.isEmpty ? 'the last terminal' : trip.stopName(trip.stops.last.stopSequence);
    final (icon, colour, words) = switch (trip) {
      _ when trip.isCompleted => (Icons.check_circle_outline, AppColors.success, 'Trip completed. Nothing left to do.'),
      _ when trip.isDeparted =>
        (Icons.flag_outlined, AppColors.primary, 'On the road. Tap Arrived at $last when everyone is off.'),
      _ when blocked => (
          Icons.sensor_occupied_outlined,
          AppColors.danger,
          'The camera counts more aboard than listed. List them as walk-ins, or explain below, before Depart.'
        ),
      _ when owing.isNotEmpty => (
          Icons.payments_outlined,
          AppColors.warning,
          'Collect ₱${cash.toStringAsFixed(0)} in cash from ${owing.length} '
              '${owing.length == 1 ? 'passenger' : 'passengers'}, then mark each one Paid.'
              '${here == 0 ? '' : ' ${here == owing.length && here == 1 ? 'They are' : '$here ${here == 1 ? 'is' : 'are'}'} here to pay now.'}'
        ),
      _ when trip.isBoarding =>
        (Icons.directions_bus_outlined, AppColors.primary, 'Everyone has paid. When all are aboard, tap Depart.'),
      _ => (
          Icons.hourglass_empty,
          AppColors.info,
          'Everyone listed has paid. The office starts the trip; then Depart appears below.'
        ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: colour, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: colour)),
            const SizedBox(height: 2),
            Text(words, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.35)),
          ]),
        ),
      ]),
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

  /// Cash the Dispatcher has already collected, or a cancel, that the
  /// server doesn't know about yet -- done in a dead zone, waiting on the
  /// queue. Never hidden: a variance the office can't see coming is worse
  /// than one flagged in advance.
  Widget _pendingSyncBanner(int walkIns, int marks, OfflineSyncService sync) => Container(
        color: AppColors.warningContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${[
                  if (walkIns > 0) '$walkIns walk-in${walkIns == 1 ? '' : 's'}',
                  if (marks > 0) '$marks mark${marks == 1 ? '' : 's'}',
                ].join(' and ')} made offline, not yet synced.',
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

  /// The trip's actions, pinned under the thumb: Add walk-in while the
  /// list is open, and the one step that moves the trip on -- Depart once
  /// the office has started it, Arrived once it is on the road -- filled,
  /// at the right, where the thumb rests. Every button is 56 high and in
  /// the same place trip after trip.
  Widget? _actionBar(CrewTrip trip, bool departed) {
    final rental = trip.rental != null;
    final walkIn = !departed && !rental;
    final Widget? main = trip.isBoarding
        ? FilledButton.icon(
            onPressed: _acting ? null : () => _depart(trip),
            icon: const Icon(Icons.logout),
            label: const Text('Depart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          )
        : departed && !trip.isCompleted
            ? FilledButton.icon(
                onPressed: _acting ? null : _arrive,
                icon: const Icon(Icons.flag),
                label: const Text('Arrived'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              )
            : null;
    if (!walkIn && main == null) return null;
    return Material(
      color: AppColors.surfaceRaised,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(children: [
            if (walkIn)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _acting ? null : () => _push(WalkInScreen(trip: trip)),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add walk-in'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            if (walkIn && main != null) const SizedBox(width: AppSpacing.sm),
            if (main != null) Expanded(child: main),
          ]),
        ),
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
                Text('${m.totalBookings} booked · ${m.seatCapacity} seats',
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
    // After departure the server closes every seat still on the trip; a
    // paid one is not called a no-show, because nobody can tell from here
    // whether that passenger rode.
    final (label, tone) = switch (p.status) {
      'boarded' => ('BOARDED', StatusTone.success),
      'pending_sync' => ('PENDING SYNC', StatusTone.info),
      _ when p.isUnpaid => (p.isNoShow ? 'NO-SHOW' : 'UNPAID', StatusTone.danger),
      'checked_in' => ('AT TERMINAL', StatusTone.info),
      _ => ('PAID', StatusTone.success),
    };
    final struck = p.isNoShow && p.isUnpaid;

    // How the passenger got on the manifest — booked ahead through the
    // app or paid cash at a terminal. A Dispatcher looks over a queue of
    // strangers; this has to be legible at a glance, not a suffix at the
    // end of a grey line.
    final (methodLabel, methodColour, methodIcon) = switch (p) {
      _ when p.isWalkIn => ('WALK-IN', AppColors.success, Icons.storefront),
      _ => ('APP BOOKING', AppColors.primary, Icons.smartphone),
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: methodColour.withValues(alpha: 0.12),
        child: Icon(methodIcon, color: methodColour, size: 20),
      ),
      title: Text(
        p.name ?? (p.isWalkIn ? 'Walk-in passenger' : 'App passenger'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: struck ? AppColors.textMuted : AppColors.textPrimary,
          decoration: struck ? TextDecoration.lineThrough : null,
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
            '${p.bookingCode} · ${trip.stopName(p.boardingStop)} → ${trip.stopName(p.alightingStop)}',
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
class _PhotoDialog extends StatelessWidget {
  const _PhotoDialog({required this.load});
  final Future<Uint8List> Function() load;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Landmark photo'),
        content: FutureBuilder<Uint8List>(
          future: load(),
          builder: (_, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return Text(e is ApiException ? e.message : 'The photo could not be loaded.');
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

/// The reservations filter on the trip screen.
enum _Show { auto, collect, paid, all }
