import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/oversight_repository.dart';

/// Boarding Audit (brief 9, replaces Passenger Count Checks). For each
/// trip of the day with door events to review: the boardings before
/// departure that matched no ticket scan or cash entry, with the
/// Dispatcher's fix or reason; the capacity alerts with their general
/// place; a departure with more aboard than listed; and the trip's hash
/// chain. The blurred stills are for the Terminal Manager only.
///
/// Nothing here estimates a fare: the camera's count prices no one.
class BoardingAuditScreen extends StatefulWidget {
  const BoardingAuditScreen({super.key});

  @override
  State<BoardingAuditScreen> createState() => _BoardingAuditScreenState();
}

class _BoardingAuditScreenState extends State<BoardingAuditScreen> {
  late final OversightRepository _oversight = context.read<OversightRepository>();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<TripAudit>? _trips;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Live: a door event the phone sends shows up without a refresh.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final trips = await _oversight.boardingAudit(isoDay(_day));
      if (mounted) setState(() => _trips = trips);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips ?? const <TripAudit>[];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Boarding Audit',
            description: 'Boardings the phone counted that were not on the passenger list, what the '
                'Dispatcher did about each, and every time a van carried more than its seats.',
            actions: [
              DayPicker(day: _day, onShift: _shift),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          Expanded(
            child: _loading && _trips == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : trips.isEmpty
                        // Says only what the phones reported: a trip whose
                        // phone sent nothing is Unaudited, never cleared.
                        ? const EmptyState(
                            icon: Icons.fact_check_outlined,
                            title: 'Nothing to review on this day',
                            hint: 'No phone reported a boarding that was not on the list, a van '
                                'over its seats, or a departure with more aboard than listed. '
                                'A trip whose phone sent nothing is Unaudited, not cleared: its '
                                'status is on Trips.')
                        : ListView.separated(
                            itemCount: trips.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
                            itemBuilder: (_, i) => _TripAuditPanel(audit: trips[i]),
                          ),
          ),
        ],
      ),
    );
  }
}

class _TripAuditPanel extends StatelessWidget {
  const _TripAuditPanel({required this.audit});
  final TripAudit audit;

  static final _time = DateFormat('h:mm:ss a');

  @override
  Widget build(BuildContext context) {
    final a = audit;
    final text = Theme.of(context).textTheme;
    final pending = a.unlisted.where((u) => u.resolution == 'pending').length;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: a.departedWithMore != null ? AppColors.danger.withValues(alpha: 0.4) : AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(6)),
            child: Text(a.plateNumber ?? 'No van',
                style: const TextStyle(color: AppColors.onFill, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.tripLabel, style: text.titleSmall),
              Text('Operator ${a.operatorName ?? '—'}${a.operatorLicence == null ? '' : ', licence ${a.operatorLicence}'}'
                  ', Dispatcher ${a.dispatcherName ?? 'none'}', style: text.bodySmall),
            ]),
          ),
          StatusBadge.trip(a.status),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
          if (a.departedWithMore != null) const StatusBadge('More aboard than listed', tone: Tone.danger),
          if (pending > 0) StatusBadge('$pending boarding${pending == 1 ? '' : 's'} not resolved', tone: Tone.warning),
          if (a.unlisted.isNotEmpty && pending == 0)
            const StatusBadge('Every boarding resolved', tone: Tone.success),
          if (a.capacityAlerts.isNotEmpty) const StatusBadge('Above the van\'s seats', tone: Tone.warning),
        ]),
        if (a.departedWithMore != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(a.departedWithMore!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        // The door camera's record and whether it is intact (the
        // reference's evidence block, with what the phones really sent).
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            Icon(a.chainVerified ? Icons.verified_outlined : Icons.gpp_bad_outlined,
                size: 18, color: a.chainVerified ? AppColors.edge : const Color(0xFFFCA5A5)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                // Plain words (12 Nov): the check underneath is a hash
                // chain over the door events, but the office reads only
                // what it means for trusting the count.
                a.chainVerified
                    ? 'Door camera record: someone got on or off ${a.chainEvents == 1 ? 'once' : '${a.chainEvents} times'}, '
                        'as the van\'s phone saw it. The record is untouched: nothing was changed or removed.'
                    : 'Door camera record changed: from entry ${a.chainBrokenAt} on, it is not what the phone sent. '
                        'Do not rely on the count from there.',
                style: const TextStyle(color: AppColors.onFill, fontSize: 13),
              ),
            ),
          ]),
        ),
        if (a.unlisted.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Boardings not on the passenger list (${a.unlisted.length})', style: text.titleSmall),
          if (a.crewAboard)
            Text('The Dispatcher marked themselves crew: one of these boardings is theirs.', style: text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(children: [for (final u in a.unlisted) _UnlistedRow(boarding: u)]),
          ),
        ],
        if (a.capacityAlerts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Above the van\'s seats (${a.capacityAlerts.length})', style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final c in a.capacityAlerts)
            FactLine(Icons.groups_outlined,
                '${_time.format(c.at)}: ${c.aboard} aboard, ${c.capacity} seats, ${c.place ?? 'place not known'}',
                colour: AppColors.warning),
        ],
      ]),
    );
  }
}

class _UnlistedRow extends StatelessWidget {
  const _UnlistedRow({required this.boarding});
  final UnlistedBoarding boarding;

  static final _time = DateFormat('h:mm:ss a');

  @override
  Widget build(BuildContext context) {
    final u = boarding;
    final text = Theme.of(context).textTheme;
    final (badge, detail) = switch (u.resolution) {
      'listed' => (const StatusBadge('Listed', tone: Tone.success),
          'Added to the list${u.listedDestination != null ? ', to ${u.listedDestination}' : ''}'),
      'explained' => (const StatusBadge('Reason given', tone: Tone.info), '"${u.note ?? ''}"'),
      _ => (const StatusBadge('Not resolved', tone: Tone.danger), 'Neither listed nor explained'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 100, child: Text(_time.format(u.at), style: text.bodySmall)),
        SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: badge)),
        Expanded(
          child: Text('$detail${u.resolvedBy != null ? ' · ${u.resolvedBy}' : ''}', style: text.bodyMedium),
        ),
        SizedBox(
          width: 170,
          child: Align(
            alignment: Alignment.centerRight,
            child: u.hasSnapshot
                ? TextButton.icon(
                    onPressed: () => _showStill(context),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('View blurred still'),
                  )
                : Text(u.snapshotDeleted ? 'Still deleted (retention)' : 'No still received',
                    style: text.bodySmall),
          ),
        ),
      ]),
    );
  }

  Future<void> _showStill(BuildContext context) async {
    final oversight = context.read<OversightRepository>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Boarding at ${_time.format(boarding.at)}'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder(
            future: oversight.snapshot(boarding.eventId),
            builder: (_, snap) {
              if (snap.hasError) {
                final e = snap.error;
                return Text(e is ApiException ? e.message : 'The still could not be loaded.');
              }
              if (!snap.hasData) {
                return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              }
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Image.memory(snap.data!, fit: BoxFit.contain),
                const SizedBox(height: AppSpacing.sm),
                Text('Faces are blurred on the phone. Shown to the Terminal Manager only.',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ]);
            },
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
