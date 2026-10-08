import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../ai_audit_queue/audit_reading_card.dart';
import '../../ai_audit_queue/phone_capture.dart';

/// The office's view of every trip on a day, as each conductor sees it.
///
/// Left: the day's trips with live status and counts. Right: the selected
/// trip's manifest -- the SAME endpoint the conductor's app reads, so the
/// office and the van door can never show two different passenger lists.
/// Status words match the conductor app exactly (AT TERMINAL, NOT YET...)
/// so a dispatcher on the phone with a conductor is using their words.
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
      setState(() {
        _trips = trips;
        _selectedId = selected;
        _error = null;
      });
      await _loadManifest();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _loadManifest() async {
    final id = _selectedId;
    if (id == null) {
      setState(() => _manifest = null);
      return;
    }
    try {
      final m = await _dispatch.manifest(id);
      if (!mounted || _selectedId != id) return;
      setState(() => _manifest = m);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
    // Separately, so an audit list that fails to load never hides the
    // manifest the conductor is working from.
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
    });
    _loadManifest();
  }

  void _shiftDay(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _trips = null;
      _selectedId = null;
      _manifest = null;
      _tripAudits = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      final pad = wide ? AppSpacing.xxl : AppSpacing.lg;
      final list = _TripList(
        trips: _trips,
        selectedId: _selectedId,
        onSelect: _select,
      );
      final detail = _ManifestPanel(
        trip: _trips?.where((t) => t.tripId == _selectedId).firstOrNull,
        manifest: _manifest,
        audits: _tripAudits,
        onCaptureFinished: _loadManifest,
      );

      return Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trips',
                          style: text.headlineSmall!.copyWith(color: AppColors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Every trip on the day, as its conductor sees it. Refreshes every '
                          '${_refreshEvery.inSeconds} s.',
                          style: text.bodySmall!.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () => _shiftDay(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  DateUtils.isSameDay(_day, DateTime.now())
                      ? 'Today, ${DateFormat.MMMd().format(_day)}'
                      : DateFormat.yMMMEd().format(_day),
                  style: text.titleSmall!.copyWith(color: AppColors.textPrimary),
                ),
                IconButton(
                  tooltip: 'Next day',
                  onPressed: () => _shiftDay(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Refresh now',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 420, child: list),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: detail),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: list),
                        const SizedBox(height: AppSpacing.lg),
                        Expanded(child: detail),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
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
    if (t == null) return const Center(child: CircularProgressIndicator());
    if (t.isEmpty) {
      return const _Panel(
        child: Center(
          child: Text('No trips on this day.', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return _Panel(
      child: ListView.separated(
        itemCount: t.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final trip = t[i];
          final selected = trip.tripId == selectedId;
          return Material(
            color: selected ? AppColors.primaryContainer : Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(trip.tripId),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(DateFormat.jm().format(trip.departureDatetime),
                          style: text.titleSmall!.copyWith(color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(trip.routeName,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium!.copyWith(
                                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              trip.plateNumber ?? 'no van',
                              'Cond. ${trip.conductorName ?? 'unassigned'}',
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall!.copyWith(color: AppColors.textMuted),
                          ),
                          Text(
                            '${trip.booked}/${trip.seatCapacity} booked · '
                            '${trip.boarded} boarded'
                            '${trip.checkedIn > 0 ? ' · ${trip.checkedIn} at terminal' : ''}',
                            style: text.bodySmall!.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _TripStatusPill(status: trip.status),
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

// --------------------------------------------------------- manifest panel
class _ManifestPanel extends StatelessWidget {
  const _ManifestPanel({
    required this.trip,
    required this.manifest,
    required this.audits,
    required this.onCaptureFinished,
  });
  final TripBoardEntry? trip;
  final TripManifest? manifest;
  final List<PendingAudit>? audits;
  final VoidCallback onCaptureFinished;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final m = manifest;
    final text = Theme.of(context).textTheme;
    if (t == null) {
      return const _Panel(
        child: Center(
          child: Text('Select a trip.', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.routeName} · ${DateFormat.jm().format(t.departureDatetime)}',
                    style: text.titleMedium!.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                // Keyed by trip: selecting another trip gets a fresh button,
                // while a capture already in flight still reports its result.
                PhoneCaptureButton(
                    key: ValueKey(t.tripId),
                    tripId: t.tripId,
                    tripStatus: t.status,
                    onFinished: onCaptureFinished),
                const SizedBox(width: AppSpacing.md),
                _TripStatusPill(status: t.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (t.tripLabel != null) t.tripLabel!,
                t.plateNumber ?? 'no van',
                'Driver ${t.driverName ?? 'unassigned'}',
                'Conductor ${t.conductorName ?? 'unassigned'}',
                if (t.departedAt != null) 'left ${DateFormat.jm().format(t.departedAt!)}',
              ].join(' · '),
              style: text.bodySmall!.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (m == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _Count('Boarded', m.boarded, AppColors.success),
                  _Count('At terminal', m.checkedIn, AppColors.info),
                  _Count('Not yet', m.awaiting, AppColors.warning),
                  _Count('Unpaid', m.unpaid, AppColors.textMuted),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // One scrolling body: the AI checks first, because they are
              // what changes when someone presses Phone capture, then the
              // passengers they were checked against.
              Expanded(
                child: ListView(
                  children: [
                    _AuditsSection(audits: audits),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Passengers',
                        style: text.titleSmall!.copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: AppSpacing.xs),
                    if (m.passengers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Text('No passengers on this trip yet.',
                            style: TextStyle(color: AppColors.textMuted)),
                      )
                    else
                      for (final (i, p) in m.passengers.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _PassengerRow(p: p),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The trip's AI headcount checks, newest first, each with what it means
/// -- so the office reads a phone capture's result here instead of leaving
/// for the YOLOv8 Audits tab.
class _AuditsSection extends StatelessWidget {
  const _AuditsSection({required this.audits});
  final List<PendingAudit>? audits;

  /// The newest few. The audits tab keeps the full trail.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = audits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI headcount checks',
            style: text.titleSmall!.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        if (a == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: LinearProgressIndicator(),
          )
        else if (a.isEmpty)
          Text(
            'No headcount check on this trip yet. Phone capture, a door close or '
            'the van leaving a terminal creates one.',
            style: text.bodySmall!.copyWith(color: AppColors.textMuted),
          )
        else ...[
          for (final audit in a.take(_shown)) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
              child: Text(
                [
                  'Leg ${audit.legSequence}',
                  DateFormat.jm().format(audit.capturedAt),
                  audit.triggerLabel,
                  'camera ${audit.visualCount} · manifest ${audit.bookedCount}',
                  _statusWords(audit.resolutionStatus),
                ].join(' · '),
                style: text.bodySmall!.copyWith(color: AppColors.textMuted),
              ),
            ),
            AuditReadingCard(audit: audit),
          ],
          if (a.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '${a.length - _shown} earlier check(s) on this trip -- see YOLOv8 Audits.',
                style: text.bodySmall!.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ],
    );
  }

  static String _statusWords(String status) => switch (status) {
        'pending' => 'awaiting review',
        'reconciled' => 'no action needed',
        'resolved' => 'resolved',
        'ignored' => 'dismissed',
        _ => status,
      };
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({required this.p});
  final ManifestPassenger p;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // App passengers are identified by ticket, as on the conductor's
    // screen; walk-ins carry the name the conductor typed.
    final who = p.name ?? p.ticketNumber;
    final detail = [
      'Stop ${p.boardingStop} → ${p.alightingStop}',
      p.bookingType == 'walk_in' ? 'walk-in, cash' : 'app',
      '₱${p.fareAmount}',
      if (p.isRoadsidePickup) 'roadside: ${p.pickupLandmark ?? 'pickup'}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(who, style: text.bodyMedium!.copyWith(color: AppColors.textPrimary)),
                Text(detail, style: text.bodySmall!.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          _PassengerStatusPill(status: p.status),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- pieces
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value',
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
}

/// Trip status in the conductor app's words.
class _TripStatusPill extends StatelessWidget {
  const _TripStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      'boarding' => (AppColors.success, 'BOARDING'),
      'departed' => (AppColors.info, 'DEPARTED'),
      'completed' => (AppColors.textMuted, 'COMPLETED'),
      'cancelled' => (AppColors.danger, 'CANCELLED'),
      _ => (AppColors.brand, 'SCHEDULED'),
    };
    return _Pill(bg: bg, label: label);
  }
}

/// Passenger status in the conductor app's words (trip_manifest_screen.dart).
class _PassengerStatusPill extends StatelessWidget {
  const _PassengerStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      'boarded' => (AppColors.success, 'BOARDED'),
      'checked_in' => (AppColors.info, 'AT TERMINAL'),
      'confirmed' => (AppColors.warning, 'NOT YET'),
      'pending' => (AppColors.textMuted, 'UNPAID'),
      'no_show' => (AppColors.danger, 'NO-SHOW'),
      'completed' => (AppColors.textMuted, 'COMPLETED'),
      _ => (AppColors.textMuted, status.toUpperCase()),
    };
    return _Pill(bg: bg, label: label);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.bg, required this.label});
  final Color bg;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
