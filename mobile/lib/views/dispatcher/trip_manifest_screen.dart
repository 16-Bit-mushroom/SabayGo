import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/dialog_buttons.dart';
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
    // taking the screen down: that panel is simply left out. Awaited in a
    // try, not `catchError(() => null)`: on a Future<Set<String>> that
    // handler's null is refused at run time (ArgumentError), which escaped
    // this method and left the screen with no list (found 20 Nov by
    // test/trip_screen_test.dart).
    Future<Object?> optional<T>(Future<T> call) async {
      try {
        return await call;
      } catch (_) {
        return null;
      }
    }
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
            DialogButtons(
              action: yes,
              onAction: () => Navigator.pop(ctx, true),
              cancel: 'Not yet',
              onCancel: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _depart(CrewTrip trip) async {
    final unpaid = (_share?.amountDue ?? 0) > 0;
    final ok = await _confirm(
      'Depart now?',
      'Boarding closes and the passenger list locks. Paid passengers count as aboard; unpaid ones '
          'become no-shows.${unpaid ? ' The terminal fees are not recorded yet: the van leaves unpaid, '
              'and its next assignment waits until the Cashier records them.' : ''}',
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
          DialogButtons(
            action: 'Arrived',
            onAction: () => Navigator.pop(ctx, true),
            cancel: 'Not yet',
            onCancel: () => Navigator.pop(ctx, false),
          ),
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

    final appBar = AppBar(
      titleSpacing: 0,
      title: Text(trip.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      // The van and its operator on a row of their own, the screen's whole
      // width: beside SOS and Refresh the line was cut to "Arnel Bautista,
      // l…" (20 Nov). Under the bar it stays in view whichever tab is open:
      // the plate is checked against the van at the door (brief 9).
      bottom: _vanStrip(context, trip),
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
    );

    if (_loading) {
      return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }
    if (m == null) return Scaffold(appBar: appBar, body: _errorView());

    final tabs = _tabs(trip, m, departed, marks, pending);
    // The trip's state and counts stay pinned above the tabs while the
    // text is a normal size (20 Nov redesign). At large system text that
    // band would leave too little room for the list, so it scrolls with
    // each tab instead (WCAG 1.4.10).
    final roomy = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    final header = _header(trip, m, marks, pending, sync);

    return DefaultTabController(
      key: ValueKey(tabs.map((t) => t.id).join('/')),
      length: tabs.length,
      child: Scaffold(
        appBar: appBar,
        // The trip's next action sits at the bottom, under the thumb, and
        // stays there while the list scrolls (Fitts).
        bottomNavigationBar: _actionBar(trip, departed),
        body: Column(
          children: [
            if (roomy)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceRaised,
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: header,
              ),
            Material(
              color: AppColors.surfaceRaised,
              child: TabBar(
                isScrollable: !roomy,
                tabAlignment: roomy ? null : TabAlignment.start,
                tabs: [for (final t in tabs) t.tab],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final t in tabs)
                    RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxl),
                        children: [
                          if (!roomy) ...[
                            DashCard(title: 'This trip', children: [header]),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          ...t.children,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The plate, then the operator's name and licence (the only way the
  /// operator is shown), under the bar at full width: one line where it
  /// fits, two on a narrow phone or at large text. Measured, because the
  /// bar must know its height before it is laid out.
  PreferredSizeWidget _vanStrip(BuildContext context, CrewTrip trip) {
    final span = TextSpan(
      style: Theme.of(context)
          .textTheme
          .bodyMedium!
          .copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted),
      children: [
        TextSpan(
          text: trip.plateNumber ?? 'No van yet',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        TextSpan(text: ' · ${trip.operatorName ?? 'operator not known'}'),
        if (trip.operatorLicence != null) TextSpan(text: ' · Licence ${trip.operatorLicence}'),
      ],
    );
    const icon = 16.0;
    const gap = 6.0;
    final painter = TextPainter(
      text: span,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - 2 * AppSpacing.gutter - icon - gap);
    final line = painter.height.ceilToDouble();
    painter.dispose();
    return PreferredSize(
      preferredSize: Size.fromHeight((line < icon ? icon : line) + AppSpacing.xs + AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.airport_shuttle_outlined, size: icon, color: AppColors.textMuted),
            const SizedBox(width: gap),
            Expanded(child: Text.rich(span, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  /// The trip's tabs, in the order of the work: who is boarding and the
  /// count that gates Depart; the home pickups (or the rental) when there
  /// are any; then the money and the driving flags. A badge says when a
  /// tab is waiting on the Dispatcher, so nothing on a hidden tab is
  /// missed.
  List<_TabSpec> _tabs(CrewTrip trip, Manifest m, bool departed, Map<String, PendingSeatMark> marks,
      List<PendingWalkIn> pending) {
    final specs = <_TabSpec>[];
    final rental = trip.rental;
    if (rental == null) {
      final excess = departed ? 0 : (_check?.excess ?? 0);
      specs.add(_TabSpec(
        'boarding',
        _tabLabel('Boarding', badge: excess > 0 ? '$excess' : null, badgeColour: AppColors.danger),
        [
          if (_check case final check? when !departed) ...[
            DoorCheckPanel(
              check: check,
              busy: _acting,
              onList: (u) => _push(WalkInScreen(trip: trip, forEventId: u.eventId, forEventAt: u.at)),
              onExplain: _explain,
              onCrew: (v) => _do(() => _ops.setCrew(trip.tripId, v),
                  v ? 'You are marked crew: not counted.' : 'You are no longer marked crew.'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          departed ? _passengerList(trip, m, pending) : _reservations(trip, marks),
        ],
      ));
    } else {
      specs.add(_TabSpec(
        'rental',
        _tabLabel('Rental', badge: rental.paymentStatus == 'paid' ? null : '!', badgeColour: AppColors.warning),
        [
          RentalPanel(
            rental: rental,
            busy: _acting,
            onCash: () => _do(() => _ops.rentalCash(rental.requestId), 'Rental fee recorded.'),
          ),
        ],
      ));
    }
    if (_pickups.isNotEmpty) {
      final waiting = HomePickupsPanel.needingAction(_pickups, departed: departed);
      specs.add(_TabSpec(
        'pickups',
        _tabLabel('Pickups', badge: waiting > 0 ? '$waiting' : null, badgeColour: AppColors.warning),
        [HomePickupsPanel(pickups: _pickups, departed: departed, busy: _acting, onAction: _pickup)],
      ));
    }
    final share = _share;
    final owes = (share?.amountDue ?? 0) > 0;
    specs.add(_TabSpec(
      'fees',
      _tabLabel('Fees & flags', badge: owes || _flags.isNotEmpty ? '!' : null, badgeColour: AppColors.warning),
      [
        if (share != null && (share.lines.isNotEmpty || share.amountDue > 0))
          SharePanel(
            share: share,
            disputedLines: _disputedLines,
            busy: _acting,
            onDispute: (l) => _dispute(line: l),
          )
        else
          _emptyCard('Nothing to hand over yet. Pull down to refresh.'),
        if (_flags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          FlagsPanel(flags: _flags, busy: _acting, onDispute: (f) => _dispute(flag: f)),
        ] else if (departed) ...[
          const SizedBox(height: AppSpacing.lg),
          _emptyCard('No driving flags on this trip.'),
        ],
      ],
    ));
    return specs;
  }

  Widget _tabLabel(String text, {String? badge, Color badgeColour = AppColors.danger}) => Tab(
        child: Semantics(
          label: badge == null ? text : '$text, needs attention',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Badge(label: Text(badge), backgroundColor: badgeColour, textColor: AppColors.onFill),
              ],
            ],
          ),
        ),
      );

  Widget _emptyCard(String text) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.edge),
        ),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
      );

  /// The trip at a glance: its state and time, four counts, and the one
  /// thing to do next. Offline marks and a non-passenger trip show here
  /// too, so they are never on a hidden tab.
  Widget _header(CrewTrip trip, Manifest m, Map<String, PendingSeatMark> marks, List<PendingWalkIn> pending,
      OfflineSyncService sync) {
    final (label, tone) = switch (m.status) {
      'boarding' => ('BOARDING', StatusTone.success),
      'departed' => ('ON THE ROAD', StatusTone.muted),
      'completed' => ('COMPLETED', StatusTone.muted),
      _ => ('SCHEDULED', StatusTone.brand),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Flexible(child: StatusChip(label, tone: tone)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              DateFormat('EEE d MMM · h:mm a').format(m.departure),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14),
            ),
          ),
        ]),
        if (trip.rental == null) ...[
          const SizedBox(height: AppSpacing.md),
          TripCounts(
            paid: m.totalBookings - m.unpaid,
            unpaid: m.unpaid,
            atTerminal: m.checkedIn,
            seatsLeft: (m.seatCapacity - m.totalBookings).clamp(0, m.seatCapacity),
          ),
          const SizedBox(height: AppSpacing.md),
          _nextStep(trip, marks),
        ],
        if (pending.isNotEmpty || marks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _pendingSyncBanner(pending.length, marks.length, sync),
        ],
        if (_move case final move?) ...[
          const SizedBox(height: AppSpacing.sm),
          _moveBanner(move),
        ],
      ],
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
    Widget note(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text('Reservations and walk-ins',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (all.loaded)
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            chip(_Show.collect, 'To collect', toCollect.length),
            chip(_Show.paid, 'Paid', paid.length),
            chip(_Show.all, 'All', live.length),
          ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
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
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!all.loaded)
          note('The list has not loaded. Pull down to try again.')
        else if (shown.isEmpty)
          note(q.isNotEmpty
              ? 'No reservation matches "${_search.text.trim()}".'
              : switch (show) {
                  _Show.collect => 'Nobody left to collect from. Everyone listed has paid.',
                  _Show.paid => 'Nobody has paid yet.',
                  _ => 'Nobody has reserved yet. Add walk-ins with the button below.',
                }),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          SeatCard(
            seat: shown[i],
            stopName: trip.stopName(shown[i].alightingStop),
            mark: marks[shown[i].bookingId],
            busy: _acting,
            onPaid: () => _markPaid(shown[i]),
            onCancel: () => _cancelSeat(shown[i]),
          ),
        ],
      ],
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
              Text(_error ?? 'The trip could not be loaded.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

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
    final (icon, tone, words) = switch (trip) {
      _ when trip.isCompleted => (Icons.check_circle_outline, StatusTone.success, 'Trip completed. Nothing left to do.'),
      _ when trip.isDeparted =>
        (Icons.flag_outlined, StatusTone.brand, 'On the road. Tap Arrived at $last when everyone is off.'),
      _ when blocked => (
          Icons.sensor_occupied_outlined,
          StatusTone.danger,
          'The camera counts more aboard than listed. Add them as walk-ins, or give a reason, before Depart.'
        ),
      _ when owing.isNotEmpty => (
          Icons.payments_outlined,
          StatusTone.warning,
          'Collect ₱${cash.toStringAsFixed(0)} in cash from ${owing.length} '
              '${owing.length == 1 ? 'passenger' : 'passengers'}, then mark each one Paid.'
              '${here == 0 ? '' : ' ${here == owing.length && here == 1 ? 'They are' : '$here ${here == 1 ? 'is' : 'are'}'} here to pay now.'}'
        ),
      _ when trip.isBoarding =>
        (Icons.directions_bus_outlined, StatusTone.brand, 'Everyone has paid. When all are aboard, tap Depart.'),
      _ => (
          Icons.hourglass_empty,
          StatusTone.info,
          'Everyone listed has paid. The office starts the trip; then Depart appears below.'
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.fg.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: tone.fg, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NEXT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: tone.fg)),
              const SizedBox(height: 2),
              Text(words,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15, height: 1.35, color: AppColors.textPrimary)),
            ]),
          ),
        ]),
      ),
    );
  }

  /// A band with a sentence and its one action, for states that are not
  /// on any tab: offline marks waiting to sync, a non-passenger trip.
  Widget _band({required StatusTone tone, required IconData icon, required String text, required Widget action}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.fg.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: tone.fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          action,
        ]),
      );

  Widget _moveBanner(NonPassengerMove move) => _band(
        tone: StatusTone.info,
        icon: Icons.no_transfer,
        text: 'Not a passenger trip (${_MoveDialog.words[move.reason] ?? move.reason}) since '
            '${DateFormat('h:mm a').format(move.startedAt)}. Ends by itself back at a terminal.',
        action: TextButton(
          onPressed: _acting ? null : () => _do(() => _ops.endMove(move.moveId), 'Not a passenger trip ended.'),
          child: const Text('End'),
        ),
      );

  /// Cash the Dispatcher has already collected, or a cancel, that the
  /// server doesn't know about yet -- done in a dead zone, waiting on the
  /// queue. Never hidden: a variance the office can't see coming is worse
  /// than one flagged in advance.
  Widget _pendingSyncBanner(int walkIns, int marks, OfflineSyncService sync) => _band(
        tone: StatusTone.warning,
        icon: Icons.cloud_off,
        text: '${[
          if (walkIns > 0) '$walkIns walk-in${walkIns == 1 ? '' : 's'}',
          if (marks > 0) '$marks mark${marks == 1 ? '' : 's'}',
        ].join(' and ')} made offline, not yet synced.',
        action: TextButton(onPressed: sync.flush, child: const Text('Sync now')),
      );

  /// The trip's actions, pinned under the thumb: Add walk-in while the
  /// list is open, and the one step that moves the trip on -- Depart once
  /// the office has started it, Arrived once it is on the road -- filled,
  /// at the right, where the thumb rests. Depart is held, with the reason
  /// said above it, while the camera counts people the list does not
  /// have: the server refuses it then anyway.
  Widget? _actionBar(CrewTrip trip, bool departed) {
    final rental = trip.rental != null;
    final walkIn = !departed && !rental;
    final excess = departed ? 0 : (_check?.excess ?? 0);
    final blocked = trip.isBoarding && excess > 0;
    final Widget? main = trip.isBoarding
        ? FilledButton.icon(
            onPressed: _acting || blocked ? null : () => _depart(trip),
            icon: const Icon(Icons.logout),
            label: const Text('Depart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight)),
          )
        : departed && !trip.isCompleted
            ? FilledButton.icon(
                onPressed: _acting ? null : _arrive,
                icon: const Icon(Icons.flag),
                label: const Text('Arrived'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight)),
              )
            : null;
    if (!walkIn && main == null) return null;
    return Material(
      color: AppColors.surfaceRaised,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.edge))),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Depart waits: $excess more aboard than listed. Add them, or give a reason, on Boarding.',
                    style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              Row(children: [
                if (walkIn)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acting ? null : () => _push(WalkInScreen(trip: trip)),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add walk-in'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(AppSizing.primaryActionHeight),
                      ),
                    ),
                  ),
                if (walkIn && main != null) const SizedBox(width: AppSpacing.sm),
                if (main != null) Expanded(child: main),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// After departure the list is locked: who is on it, how they got on it
  /// and what they paid.
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

    return DashCard(
      title: 'Passenger list',
      trailing: const StatusChip('LOCKED', tone: StatusTone.muted, icon: Icons.lock_outline),
      // No "7 booked · 14 seats" line here (20 Nov): the four counts at the
      // top already say how many are booked and how many seats are left.
      children: [
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text('Nobody booked.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          ),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _passengerTile(trip, visible[i]),
        ],
      ],
    );
  }

  Widget _passengerTile(CrewTrip trip, ManifestPassenger p) {
    // After departure the server closes every seat still on the trip: a
    // paid one boarded, an unpaid one a no-show.
    final (label, tone) = switch (p.status) {
      'boarded' => ('BOARDED', StatusTone.success),
      'pending_sync' => ('NOT SYNCED', StatusTone.info),
      _ when p.isUnpaid => (p.isNoShow ? 'NO-SHOW' : 'UNPAID', StatusTone.danger),
      'checked_in' => ('AT TERMINAL', StatusTone.info),
      _ => ('PAID', StatusTone.success),
    };
    final struck = p.isNoShow && p.isUnpaid;

    // How the passenger got on the list -- booked ahead through the app or
    // paid cash at the door. A Dispatcher looks over a queue of strangers;
    // this has to be legible at a glance.
    final (methodLabel, methodIcon) = p.isWalkIn ? ('WALK-IN', Icons.storefront) : ('APP BOOKING', Icons.smartphone);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryContainer,
          child: Icon(methodIcon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              p.name ?? (p.isWalkIn ? 'Walk-in passenger' : 'App passenger'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: struck ? AppColors.textMuted : AppColors.textPrimary,
                decoration: struck ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(methodLabel,
                style: const TextStyle(
                    color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            Text(
              '${p.bookingCode} · ${trip.stopName(p.boardingStop)} → ${trip.stopName(p.alightingStop)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ]),
        ),
        const SizedBox(width: AppSpacing.lg),
        // The state and the fare at the card's right edge, under the
        // LOCKED chip, a clear gap from the name and the route, which take
        // the rest of the row. As a Flexible beside the Expanded it took
        // half the free width: the route wrapped to four lines and the chip
        // sat against it (20 Nov). Capped, so a long state at large text
        // ellipsises before it squeezes the name.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusChip(label, tone: tone),
            const SizedBox(height: 4),
            Text(p.isPendingSync ? '—' : '₱${p.fare.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

/// One tab of the trip screen: an id that keys the tab set, the label,
/// and what it shows.
class _TabSpec {
  const _TabSpec(this.id, this.tab, this.children);
  final String id;
  final Widget tab;
  final List<Widget> children;
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
          DialogButtons(
            action: 'Save',
            onAction: !widget.required || _text.text.trim().length >= 3
                ? () => Navigator.pop(context, _text.text.trim())
                : null,
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
          DialogButtons(
            action: 'Leave',
            onAction: _reason != 'other' || _note.text.trim().isNotEmpty
                ? () => Navigator.pop(context, (_reason, _note.text.trim()))
                : null,
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
