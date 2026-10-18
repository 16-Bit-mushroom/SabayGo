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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
            technicalNote: 'Passenger_Events · hash chain',
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
                        ? const EmptyState(
                            icon: Icons.verified_outlined,
                            title: 'Nothing to review on this day',
                            hint: 'Every boarding matched the passenger list, and no van carried '
                                'more than its seats.')
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
    return Panel(
      title: a.tripLabel,
      icon: Icons.directions_bus_outlined,
      trailing: StatusBadge.trip(a.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FactLine(Icons.badge_outlined,
              'Operator ${a.operatorName ?? '—'}, licence ${a.operatorLicence ?? '—'}, plate ${a.plateNumber ?? '—'}'
              ' · Dispatcher ${a.dispatcherName ?? 'none'}'),
          a.chainVerified
              ? FactLine(Icons.link, 'Hash chain holds over ${a.chainEvents} door events: none was '
                  'changed, removed or reordered.', colour: AppColors.success)
              : FactLine(Icons.link_off, 'Hash chain broken at event ${a.chainBrokenAt}: the record '
                  'from there on was altered.', colour: AppColors.danger),
          if (a.departedWithMore != null)
            FactLine(Icons.warning_amber_rounded, a.departedWithMore!, colour: AppColors.danger),
          if (a.unlisted.isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            Text('Boardings not on the passenger list (${a.unlisted.length}'
                '${pending > 0 ? ', $pending not resolved' : ''})', style: text.titleSmall),
            if (a.crewAboard)
              Text('The Dispatcher marked themselves crew: one of these boardings is theirs.',
                  style: text.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            for (final u in a.unlisted) _UnlistedRow(boarding: u),
          ],
          if (a.capacityAlerts.isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            Text('Above the van\'s seats (${a.capacityAlerts.length})', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            for (final c in a.capacityAlerts)
              FactLine(Icons.groups_outlined,
                  '${_time.format(c.at)}: ${c.aboard} aboard, ${c.capacity} seats, ${c.place ?? 'place not known'}',
                  colour: AppColors.warning),
          ],
        ],
      ),
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
