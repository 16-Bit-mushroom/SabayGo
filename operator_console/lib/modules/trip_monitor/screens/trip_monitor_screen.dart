import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../ai_audit_queue/audit_reading_card.dart';
import '../../ai_audit_queue/phone_capture.dart';

/// The office's view of every trip on a day, as each conductor sees it.
///
/// Left: the day's trips with live status and counts. Right: the selected
/// trip as a set of panels -- the trip, its crew and seats, its camera
/// checks, its passenger list. The passenger list is the SAME endpoint the
/// conductor's app reads, so the office and the van door can never show
/// two different lists. Status words match the conductor app (Boarded, At
/// terminal, Not yet boarded) so a dispatcher on the phone with a
/// conductor is using their words.
///
/// Stops are named, not numbered: "Toril → Bangkal" rather than "Stop 1 →
/// 3", from the trip's own stop list (`GET /trips/{id}/stops`).
class TripMonitorScreen extends StatefulWidget {
  const TripMonitorScreen({super.key});

  @override
  State<TripMonitorScreen> createState() => _TripMonitorScreenState();
}

class _TripMonitorScreenState extends State<TripMonitorScreen> {
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final AuditRepository _auditRepo = context.read<AuditRepository>();

  /// Boarding and departures change minute to minute; the conductor is
  /// scanning while the office watches.
  static const _refreshEvery = Duration(seconds: 15);

  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<TripBoardEntry>? _trips;
  String? _selectedId;
  TripManifest? _manifest;
  List<PendingAudit>? _tripAudits;
  Map<int, String> _stopNames = const {};
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final trips = await _dispatch.tripBoard(_day);
      if (!mounted) return;
      // Keep the selection across refreshes; otherwise default to the trip
      // that matters most right now -- one under way, else the first.
      var selected = _selectedId;
      if (selected == null || !trips.any((t) => t.tripId == selected)) {
        selected = trips
                .where((t) => t.status == 'boarding' || t.status == 'departed')
                .firstOrNull
                ?.tripId ??
            trips.firstOrNull?.tripId;
      }
      final changed = selected != _selectedId;
      setState(() {
        _trips = trips;
        _selectedId = selected;
        _error = null;
      });
      await _loadManifest(withStops: changed);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _loadManifest({bool withStops = false}) async {
    final id = _selectedId;
    if (id == null) {
      setState(() => _manifest = null);
      return;
    }
    if (withStops) {
      // Names only: a failure leaves "Stop 2" wording, never a blank.
      try {
        final stops = await _dispatch.tripStops(id);
        if (!mounted || _selectedId != id) return;
        setState(() => _stopNames = {for (final s in stops) s.sequence: s.name});
      } on ApiException {
        if (mounted) setState(() => _stopNames = const {});
      }
    }
    try {
      final m = await _dispatch.manifest(id);
      if (!mounted || _selectedId != id) return;
      setState(() => _manifest = m);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
    // Separately, so a check list that fails to load never hides the
    // passenger list the conductor is working from.
    try {
      final audits = await _auditRepo.forTrip(id);
      if (!mounted || _selectedId != id) return;
      setState(() => _tripAudits = audits);
    } on ApiException {
      if (!mounted || _selectedId != id) return;
      setState(() => _tripAudits = const []);
    }
  }

  void _select(String id) {
    setState(() {
      _selectedId = id;
      _manifest = null;
      _tripAudits = null;
      _stopNames = const {};
    });
    _loadManifest(withStops: true);
  }

  void _shiftDay(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _trips = null;
      _selectedId = null;
      _manifest = null;
      _tripAudits = null;
      _stopNames = const {};
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 1000;
      final list = _TripList(trips: _trips, selectedId: _selectedId, onSelect: _select);
      final detail = _TripDetail(
        trip: _trips?.where((t) => t.tripId == _selectedId).firstOrNull,
        manifest: _manifest,
        audits: _tripAudits,
        stopNames: _stopNames,
        onCaptureFinished: _loadManifest,
      );

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Trips',
              description: 'Every trip on the chosen day, as its conductor sees it. Pick a '
                  'trip to see who is aboard. Updates every ${_refreshEvery.inSeconds} seconds.',
              actions: [
                _DayPicker(day: _day, onShift: _shiftDay),
                RefreshButton(onPressed: _load),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 400, child: list),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: detail),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: list),
                        const SizedBox(height: AppSpacing.lg),
                        Expanded(flex: 2, child: detail),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.day, required this.onShift});
  final DateTime day;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, DateTime.now());
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => onShift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            today ? 'Today, ${DateFormat.MMMd().format(day)}' : DateFormat.yMMMEd().format(day),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => onShift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- trip list
class _TripList extends StatelessWidget {
  const _TripList({required this.trips, required this.selectedId, required this.onSelect});
  final List<TripBoardEntry>? trips;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = trips;
    final text = Theme.of(context).textTheme;
    return Panel(
      title: t == null ? 'Trips on this day' : 'Trips on this day (${t.length})',
      icon: Icons.departure_board_outlined,
      fill: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: t == null
          ? const Center(child: CircularProgressIndicator())
          : t.isEmpty
              ? const EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No trips on this day',
                  hint: 'Trips come from the Timetable ("Create upcoming trips") or from '
                      'Special Trips.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: t.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, i) {
                    final trip = t[i];
                    final selected = trip.tripId == selectedId;
                    return Material(
                      color: selected ? AppColors.surfaceSunken : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide(
                            color: selected ? AppColors.textMuted : Colors.transparent),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => onSelect(trip.tripId),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(DateFormat.jm().format(trip.departureDatetime),
                                    style: text.titleSmall),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(trip.routeName,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodyMedium!
                                            .copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        trip.plateNumber ?? 'No van yet',
                                        'Conductor: ${trip.conductorName ?? 'not assigned'}',
                                      ].join(' · '),
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodySmall,
                                    ),
                                    Text(
                                      '${trip.booked} of ${trip.seatCapacity} seats booked · '
                                      '${trip.boarded} aboard'
                                      '${trip.checkedIn > 0 ? ' · ${trip.checkedIn} at terminal' : ''}',
                                      style: text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              StatusBadge.trip(trip.status),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ----------------------------------------------------------- trip detail
class _TripDetail extends StatelessWidget {
  const _TripDetail({
    required this.trip,
    required this.manifest,
    required this.audits,
    required this.stopNames,
    required this.onCaptureFinished,
  });
  final TripBoardEntry? trip;
  final TripManifest? manifest;
  final List<PendingAudit>? audits;
  final Map<int, String> stopNames;
  final VoidCallback onCaptureFinished;

  String _stop(int seq) => stopNames[seq] ?? 'Stop $seq';

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final m = manifest;
    final text = Theme.of(context).textTheme;
    if (t == null) {
      return const Panel(
        child: EmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Pick a trip',
          hint: 'Choose a trip on the left to see its passengers, crew and camera checks.',
        ),
      );
    }
    return ListView(
      children: [
        // The trip: what, when, which van -- and the one action on it.
        Panel(
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
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(t.routeName, style: text.titleLarge),
                            StatusBadge.trip(t.status),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          [
                            'Leaves ${DateFormat.jm().format(t.departureDatetime)}',
                            if (t.departedAt != null)
                              'left at ${DateFormat.jm().format(t.departedAt!)}',
                            t.plateNumber ?? 'no van assigned',
                            if (t.tripLabel != null) t.tripLabel!,
                          ].join(' · '),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Keyed by trip: selecting another trip gets a fresh button,
                  // while a capture already in flight still reports its result.
                  PhoneCaptureButton(
                    key: ValueKey(t.tripId),
                    tripId: t.tripId,
                    tripStatus: t.status,
                    onFinished: onCaptureFinished,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (m == null)
                const LinearProgressIndicator()
              else
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                          label: 'Aboard', value: '${m.boarded}', color: AppColors.success),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                          label: 'At terminal', value: '${m.checkedIn}', color: AppColors.info),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                          label: 'Not yet boarded',
                          value: '${m.awaiting}',
                          color: AppColors.warning),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatTile(label: 'Unpaid', value: '${m.unpaid}')),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Crew and seats side by side, as the reference pairs driver and load.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Panel(
                  title: 'Crew',
                  icon: Icons.badge_outlined,
                  child: Column(
                    children: [
                      PersonRow(role: 'Driver', name: t.driverName),
                      const SizedBox(height: AppSpacing.sm),
                      PersonRow(role: 'Conductor', name: t.conductorName),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: _SeatsPanel(trip: t)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChecksPanel(audits: audits, stop: _stop),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          title: m == null ? 'Passenger list' : 'Passenger list (${m.passengers.length})',
          icon: Icons.people_alt_outlined,
          child: m == null
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: LinearProgressIndicator(),
                )
              : m.passengers.isEmpty
                  ? Text('No passengers on this trip yet.', style: text.bodySmall)
                  : Column(
                      children: [
                        for (final (i, p) in m.passengers.indexed) ...[
                          if (i > 0) const Divider(),
                          _PassengerRow(p: p, stop: _stop),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

class _SeatsPanel extends StatelessWidget {
  const _SeatsPanel({required this.trip});
  final TripBoardEntry trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cap = trip.seatCapacity;
    double share(int n) => cap <= 0 ? 0 : (n / cap).clamp(0, 1).toDouble();
    Widget bar(String label, int n, Color colour) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: text.bodySmall)),
                  Text('$n of $cap', style: text.labelLarge),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: LinearProgressIndicator(
                  value: share(n),
                  minHeight: 6,
                  color: colour,
                  backgroundColor: AppColors.divider,
                ),
              ),
            ],
          ),
        );
    return Panel(
      title: 'Seats',
      icon: Icons.event_seat_outlined,
      child: Column(
        children: [
          bar('Booked', trip.booked, AppColors.info),
          bar('Aboard now', trip.boarded, AppColors.success),
          if (trip.noShow > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${trip.noShow} no-show', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// The trip's camera headcount checks, newest first, each with what it
/// means -- so the office reads a phone capture's result here instead of
/// leaving for Passenger Count Checks.
class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.audits, required this.stop});
  final List<PendingAudit>? audits;
  final String Function(int) stop;

  /// The newest few. Passenger Count Checks keeps the full trail.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = audits;
    return Panel(
      title: 'Camera passenger checks',
      icon: Icons.fact_check_outlined,
      trailing: Text('YOLOv8', style: text.labelMedium),
      child: a == null
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: LinearProgressIndicator(),
            )
          : a.isEmpty
              ? Text(
                  'No camera check on this trip yet. One is made when the van departs, '
                  'when it leaves a stop, or when you press "Check with phone camera".',
                  style: text.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, audit) in a.take(_shown).indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                'Section ${audit.legSequence}: ${stop(audit.legSequence)} → '
                                    '${stop(audit.legSequence + 1)}',
                                DateFormat.jm().format(audit.capturedAt),
                                audit.triggerLabel,
                              ].join(' · '),
                              style: text.bodySmall,
                            ),
                          ),
                          auditOutcomeBadge(audit.resolutionStatus),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Camera counted ${audit.visualCount} · passenger list has '
                        '${audit.bookedCount}',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AuditReadingCard(audit: audit),
                    ],
                    if (a.length > _shown)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          '${a.length - _shown} earlier check(s) on this trip are in '
                          'Passenger Count Checks.',
                          style: text.bodySmall,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({required this.p, required this.stop});
  final ManifestPassenger p;
  final String Function(int) stop;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // App passengers are identified by ticket, as on the conductor's
    // screen; walk-ins carry the name the conductor typed.
    final who = p.name ?? 'Ticket ${p.ticketNumber}';
    final detail = [
      '${stop(p.boardingStop)} → ${stop(p.alightingStop)}',
      p.bookingType == 'walk_in' ? 'walk-in, paid cash' : 'booked in app',
      '₱${p.fareAmount}',
      if (p.isRoadsidePickup) 'picked up on the road: ${p.pickupLandmark ?? 'no landmark'}',
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
          StatusBadge.passenger(p.status),
        ],
      ),
    );
  }
}
