import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../viewmodels/auth_provider.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../data/repositories/money_repository.dart';
import '../add_trips.dart';
import '../post_trip_box.dart';
import '../trip_actions.dart';
import '../trip_lifecycle_panel.dart';
import '../trip_sheet.dart';

/// Trips (11 Nov): the day as a **trip sheet**, with **Post a trip** above
/// it for the Terminal Manager (the office asked for "an automated Excel"
/// and posting "like a post"). One row a trip: van and Dispatcher picked
/// in their cells, passengers, fares and terminal fees filling themselves,
/// one next step. A click on a row opens the trip's detail from the right
/// -- its crew, start, departure, camera checks and passenger list -- so
/// the sheet keeps the page's width.
///
/// The passenger list is the SAME endpoint the Dispatcher's app reads, so
/// the office and the van door never show two lists; its names are the
/// Dispatcher's and the Terminal Manager's (the Cashier sees counts).
/// Stops are named from the trip's own stop list (`GET /trips/{id}/stops`).
class TripMonitorScreen extends StatefulWidget {
  const TripMonitorScreen({super.key});

  @override
  State<TripMonitorScreen> createState() => _TripMonitorScreenState();
}

class _TripMonitorScreenState extends State<TripMonitorScreen> {
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final MoneyRepository _money = context.read<MoneyRepository>();
  late final UserRole? _role = context.read<AuthProvider>().profile?.role;
  late final bool _manager = _role?.isManager ?? false;
  late final bool _cashier = _role?.isCashier ?? false;

  /// Boarding and departures change minute to minute.
  static const _refreshEvery = Duration(seconds: 15);

  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<TripBoardEntry>? _trips;
  List<Statement>? _statements;
  (List<Van>, List<StaffMember>)? _roster;
  String? _error;
  Timer? _timer;

  /// The post box's split view (with the passengers' list) instead of the
  /// compact bar.
  bool _split = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRoster();
    _timer = Timer.periodic(_refreshEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final trips = await _dispatch.tripBoard(_day);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    // Fares and fees come from the van statements; the sheet shows "—"
    // where they did not load rather than a zero.
    try {
      final statements = await _money.statements(_iso(_day));
      if (mounted) setState(() => _statements = statements);
    } on ApiException {
      if (mounted) setState(() => _statements = null);
    }
  }

  Future<void> _loadRoster() async {
    try {
      final r = await assignableRoster(context.read<FleetRepository>());
      if (mounted) setState(() => _roster = r);
    } on ApiException {
      // The cells then offer only the van and Dispatcher already on a trip.
    }
  }

  void _shiftDay(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _trips = null;
      _statements = null;
    });
    _load();
  }

  void _open(TripBoardEntry trip, TripMoney? money) => showTripDetail(context,
      trip: trip,
      day: _day,
      money: money,
      roster: _roster,
      isManager: _manager,
      isCashier: _cashier,
      onChanged: _load);

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    final open = OpenForBooking.openOf(trips ?? const []).length;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: [
        PageHeader(
          title: 'Trips',
          description: 'Assign a validated van and Dispatcher at the van\'s turn. Start waits until the terminal '
              'fees are recorded, or the Terminal Manager lifts the block with a written reason.',
          actions: [
            // 12 Nov: posting is a button that opens a window, not a form
            // across the page; the week's trips from the schedules beside it.
            if (_manager) ...[
              FilledButton.icon(
                onPressed: () => showPostTripDialog(context, roster: _roster, onPosted: _load),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Post a trip'),
              ),
              Tooltip(
                message: 'Makes bookable trips from every trip schedule in use, for the next 7 days. '
                    'Trips already posted are left as they are.',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (await addUpcomingTrips(context)) _load();
                  },
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: const Text('Post 7 days of trips'),
                ),
              ),
              Tooltip(
                message: 'Trips passengers can book now. Click to show or hide the list.',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _split ? AppColors.primaryContainer : null,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => setState(() => _split = !_split),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const LiveDot(),
                    const SizedBox(width: AppSpacing.sm),
                    Text('$open open for booking', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
            DayPicker(day: _day, onShift: _shiftDay),
            RefreshButton(onPressed: _load),
          ],
        ),
        if (_error != null && trips != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(_error!, style: TextStyle(color: AppColors.danger)),
          ),
        // "N open for booking" shows the passengers' list above the sheet.
        if (_manager && _split) ...[
          OpenForBooking(trips: trips ?? const []),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (_error != null && trips == null)
          SizedBox(height: 320, child: LoadError(message: _error!, onRetry: _load))
        else if (trips == null)
          const Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: Center(child: CircularProgressIndicator()))
        else if (trips.isEmpty)
          Panel(
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No trips on this day',
              hint: _manager
                  ? 'Post a trip, or post 7 days of trips from the schedules.'
                  : 'The Terminal Manager posts the day\'s trips.',
            ),
          )
        else
          TripSheet(
            trips: trips,
            statements: _statements,
            roster: _roster,
            isManager: _manager,
            isCashier: _cashier,
            onOpen: _open,
            onChanged: _load,
          ),
      ],
    );
  }
}

// ----------------------------------------------------- trip detail sheet
/// Opens a trip's detail from the right, over the sheet (the reference's
/// slide-over): its state and fees at the top, the door camera's count,
/// the van and Dispatcher, the fees worked out, the passenger list, the
/// Terminal Manager's controls, and the trip's next step at the foot. It
/// keeps itself fresh every 15 s and refreshes the sheet after each step.
Future<void> showTripDetail(
  BuildContext context, {
  required TripBoardEntry trip,
  required DateTime day,
  required TripMoney? money,
  required (List<Van>, List<StaffMember>)? roster,
  required bool isManager,
  required bool isCashier,
  required VoidCallback onChanged,
}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the trip',
      barrierColor: AppColors.scrim,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width.clamp(320.0, 560.0),
          height: double.infinity,
          child: _TripDetailSheet(
            trip: trip,
            day: day,
            money: money,
            roster: roster,
            isManager: isManager,
            isCashier: isCashier,
            onChanged: onChanged,
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class _TripDetailSheet extends StatefulWidget {
  const _TripDetailSheet({
    required this.trip,
    required this.day,
    required this.money,
    required this.roster,
    required this.isManager,
    required this.isCashier,
    required this.onChanged,
  });
  final TripBoardEntry trip;
  final DateTime day;
  final TripMoney? money;
  final (List<Van>, List<StaffMember>)? roster;
  final bool isManager;
  final bool isCashier;
  final VoidCallback onChanged;

  @override
  State<_TripDetailSheet> createState() => _TripDetailSheetState();
}

class _TripDetailSheetState extends State<_TripDetailSheet> {
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final MoneyRepository _moneyRepo = context.read<MoneyRepository>();
  late TripBoardEntry _trip = widget.trip;
  late TripMoney? _money = widget.money;
  TripManifest? _manifest;
  Map<int, String> _stopNames = const {};
  String? _listError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadStops();
    _loadManifest();
    // Opened without its figures (from Review Starts): fetch them now,
    // not on the first 15 s round, so the fees never show dashes.
    if (widget.money == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(quiet: true);
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStops() async {
    try {
      final stops = await _dispatch.tripStops(_trip.tripId);
      if (mounted) setState(() => _stopNames = {for (final s in stops) s.sequence: s.name});
    } on ApiException {
      // "Stop 2" wording, never a blank.
    }
  }

  Future<void> _loadManifest() async {
    if (!widget.isManager) return;
    try {
      final m = await _dispatch.manifest(_trip.tripId);
      if (mounted) {
        setState(() {
          _manifest = m;
          _listError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _listError = e.message);
    }
  }

  Future<void> _refresh({bool quiet = false}) async {
    try {
      final d = widget.day;
      final iso = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final results = await Future.wait([_dispatch.tripBoard(d), _moneyRepo.statements(iso)]);
      final trips = results[0] as List<TripBoardEntry>;
      final fresh = trips.where((t) => t.tripId == _trip.tripId).firstOrNull;
      if (mounted && fresh != null) {
        setState(() {
          _trip = fresh;
          _money = tripMoneyFor(fresh, trips, results[1] as List<Statement>);
        });
      }
    } on ApiException {
      // Keep what is shown; the sheet behind says if the board failed.
    }
    await _loadManifest();
    if (!quiet) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = _trip;
    final m = _money;
    final paid = t.paymentStatus == 'paid' || (t.status != 'scheduled' && t.paymentStatus != 'left_unpaid');
    return Material(
      color: AppColors.surfaceRaised,
      elevation: 8,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The trip, its state and its fees, and who drives it.
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.sm, AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                    TripStatusPill(t),
                    // The status already says "Fees due" before the start;
                    // the second badge only adds what it does not say
                    // (12 Nov UI run: two badges said the same thing).
                    if (m != null && (paid || t.status != 'scheduled'))
                      paid
                          ? const StatusBadge('Terminal fees recorded', tone: Tone.success)
                          : const StatusBadge('Terminal fees unpaid', tone: Tone.warning),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text('${DateFormat.jm().format(t.departureDatetime)} · ${t.routeName}', style: text.titleLarge),
                  Text(
                    t.operatorName == null
                        ? 'No van yet: assign one at the van\'s turn.'
                        : 'Operator: ${t.operatorName}${t.plateNumber == null ? '' : ', drives ${t.plateNumber}'}',
                    style: text.bodySmall,
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Expanded(
            child: _TripDetail(
              trip: t,
              money: m,
              roster: widget.roster,
              manifest: _manifest,
              readsList: widget.isManager,
              listError: _listError,
              onRetryList: _loadManifest,
              stopNames: _stopNames,
              onLifecycleChanged: _refresh,
            ),
          ),
          // The trip's next step, as on its row.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TripNextStep(
                trip: t,
                isManager: widget.isManager,
                isCashier: widget.isCashier,
                onChanged: _refresh,
                wide: true,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------- trip detail
class _TripDetail extends StatelessWidget {
  const _TripDetail({
    required this.trip,
    required this.money,
    required this.roster,
    required this.manifest,
    required this.readsList,
    required this.listError,
    required this.onRetryList,
    required this.stopNames,
    required this.onLifecycleChanged,
  });
  final TripBoardEntry trip;
  final TripMoney? money;
  final (List<Van>, List<StaffMember>)? roster;
  final TripManifest? manifest;
  final bool readsList;
  final String? listError;
  final VoidCallback onRetryList;
  final Map<int, String> stopNames;
  final VoidCallback onLifecycleChanged;

  String _stop(int seq) => stopNames[seq] ?? 'Stop $seq';

  static String _unaudited(String? reason) => switch (reason) {
        'no_phone' => 'No phone was out with the van',
        'silent_at_start' => 'The phone was silent at the start',
        'lost_en_route' => 'The phone went silent on the road',
        'lens_blocked' => 'The camera was covered',
        _ => 'No camera evidence',
      };

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final m = manifest;
    final text = Theme.of(context).textTheme;
    Widget tile(String label, String value, {String? note, Color? colour}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: text.bodySmall),
              Text(value,
                  style: text.titleLarge?.copyWith(color: colour, fontFeatures: const [FontFeature.tabularFigures()])),
              if (note != null) Text(note, style: text.bodySmall),
            ]),
          ),
        );
    Widget line(String label, double value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: strong ? text.titleSmall : text.bodyMedium?.copyWith(color: AppColors.textMuted))),
            Text(peso.format(value),
                style: (strong ? text.titleSmall?.copyWith(color: AppColors.primary) : text.bodyMedium)
                    ?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    final cameraNote = t.auditStatus == 'unaudited'
        ? _unaudited(t.unauditedReason)
        : t.phoneSilent == null
            ? 'No phone out with the van'
            : t.phoneSilent == true
                ? 'The phone is silent'
                : 'Phone reporting${t.phoneBatteryPct != null ? ', battery ${t.phoneBatteryPct} %' : ''}';

    return ListView(padding: const EdgeInsets.all(AppSpacing.xl), children: [
      // The door camera: what the list says beside what the phone counted.
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.videocam_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Door camera (YOLOv8)', style: text.titleSmall)),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            tile('Listed (booked + walk-in)', '${t.booked} of ${t.seatCapacity}',
                note: m == null ? null : '${m.boarded} boarded on the list'),
            const SizedBox(width: AppSpacing.md),
            tile('Aboard now (camera)', t.doorAboard == null ? 'Not counted' : '${t.doorAboard} aboard',
                note: cameraNote, colour: t.doorAboard == null ? AppColors.textMuted : AppColors.primary),
          ]),
        ]),
      ),
      const SizedBox(height: AppSpacing.lg),
      // The van and the Dispatcher: picked here or in the row while the
      // trip waits to start.
      Row(children: [
        Expanded(child: _Assign(trip: t, roster: roster, van: true, onChanged: onLifecycleChanged)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _Assign(trip: t, roster: roster, van: false, onChanged: onLifecycleChanged)),
      ]),
      const SizedBox(height: AppSpacing.lg),
      // The terminal fees worked out, from the van's statement.
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: money == null
            ? Text('The fees appear once a van is assigned.', style: text.bodySmall)
            : Column(children: [
                line('Listed fares (B + W)', money!.fares),
                line('A2Z\'s 15 %', money!.share),
                line('DCOTT ticket', money!.dcott),
                if (money!.parking > 0) line('Parking, the van\'s first trip today', money!.parking),
                const Divider(height: AppSpacing.lg),
                line('Terminal fees, before Start', money!.fees, strong: true),
                line('Operator\'s share', money!.operatorShare),
              ]),
      ),
      if (readsList) ...[
        const SizedBox(height: AppSpacing.lg),
        Panel(
          title: m == null ? 'Passenger list' : 'Passenger list (${m.passengers.length})',
          icon: Icons.people_alt_outlined,
          child: listError != null
              ? Row(children: [
                  Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('The list did not load: $listError',
                        style: text.bodySmall!.copyWith(color: AppColors.danger)),
                  ),
                  TextButton(onPressed: onRetryList, child: const Text('Try again')),
                ])
              : m == null
                  ? const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LinearProgressIndicator())
                  : m.passengers.isEmpty
                      ? Text('No passengers on this trip yet.', style: text.bodySmall)
                      : Column(children: [
                          for (final (i, p) in m.passengers.indexed) ...[
                            if (i > 0) const Divider(),
                            _PassengerRow(p: p, stop: _stop),
                          ],
                        ]),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      TripLifecyclePanel(trip: t, onChanged: onLifecycleChanged, besideSheet: true),
    ]);
  }
}

/// The trip's van or Dispatcher: a dropdown while the trip waits to start
/// (saved at once, the same as the row's cell), then the name.
class _Assign extends StatelessWidget {
  const _Assign({required this.trip, required this.roster, required this.van, required this.onChanged});
  final TripBoardEntry trip;
  final (List<Van>, List<StaffMember>)? roster;
  final bool van;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final text = Theme.of(context).textTheme;
    final current = van ? t.vanId : t.dispatcherId;
    final items = <(String, String)>[
      if (van)
        for (final v in roster?.$1 ?? const <Van>[]) (v.vanId, '${v.plateNumber}, ${v.operatorName ?? 'no operator'}')
      else
        for (final d in roster?.$2 ?? const <StaffMember>[]) (d.userId, d.fullName),
    ];
    if (current != null && !items.any((i) => i.$1 == current)) {
      items.add((current, van ? (t.plateNumber ?? 'Van') : (t.dispatcherName ?? 'Dispatcher')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(van ? 'Assigned van' : 'Assigned Dispatcher', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpacing.xs),
      if (t.status != 'scheduled')
        Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Text((van ? t.plateNumber : t.dispatcherName) ?? '—',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        )
      else
        DropdownButtonFormField<String>(
          initialValue: items.any((i) => i.$1 == current) ? current : null,
          isExpanded: true,
          hint: Text(van ? 'Pick a van' : 'Pick a Dispatcher'),
          items: [for (final (id, label) in items) DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis))],
          onChanged: (id) {
            if (id == null || id == current) return;
            TripActions(t, onChanged).assign(context, vanId: van ? id : null, dispatcherId: van ? null : id);
          },
        ),
    ]);
  }
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({required this.p, required this.stop});
  final ManifestPassenger p;
  final String Function(int) stop;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Name and booking code, as on the Dispatcher's screen; a walk-in
    // may be anonymous.
    final walkIn = p.bookingType == 'walk_in';
    final who = p.name ?? (walkIn ? 'Walk-in passenger' : 'App passenger');
    final detail = [
      p.bookingCode,
      '${stop(p.boardingStop)} → ${stop(p.alightingStop)}',
      walkIn ? 'walk-in, paid cash' : 'booked in app',
      '₱${p.fareAmount}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(who, style: text.bodyMedium),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
          StatusBadge.passenger(p.status, paid: p.isPaid),
        ],
      ),
    );
  }
}
