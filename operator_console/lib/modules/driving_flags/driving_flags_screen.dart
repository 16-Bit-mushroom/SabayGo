import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/money_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Driving flags (brief 6.4) from the van's GPS readings: overspeed on a
/// stretch, a slow stretch, an unscheduled stop. Each is an indicator for
/// review, not proof of misconduct, and names a person only through the
/// operator and plate copied onto the trip at its start.
///
/// The Terminal Manager marks a flag reviewed or dismisses it with a
/// reason; the Cashier or the Terminal Manager records the operator's
/// dispute, and deciding that dispute reviews the flag.
class DrivingFlagsScreen extends StatefulWidget {
  const DrivingFlagsScreen({super.key});

  @override
  State<DrivingFlagsScreen> createState() => _DrivingFlagsScreenState();
}

class _DrivingFlagsScreenState extends State<DrivingFlagsScreen> {
  late final OversightRepository _oversight = context.read<OversightRepository>();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _openOnly = true;
  bool _showRecorded = false;
  List<DrivingFlag>? _flags;
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
      final flags = await _oversight.drivingFlags(day: isoDay(_day), status: _openOnly ? 'open' : null);
      if (mounted) setState(() => _flags = flags);
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
    final flags = [for (final f in _flags ?? const <DrivingFlag>[]) if (_showRecorded || f.flagged) f];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Driving Flags',
            technicalNote: 'Driving_Events · NAHGM',
            description: 'Overspeed, slow stretches and unscheduled stops found in each trip\'s GPS '
                'readings. Each is for review, not proof of misconduct.',
            actions: [
              DayPicker(day: _day, onShift: _shift),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          Wrap(spacing: AppSpacing.lg, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Open')),
                ButtonSegment(value: false, label: Text('All')),
              ],
              selected: {_openOnly},
              onSelectionChanged: (s) {
                setState(() => _openOnly = s.first);
                _load();
              },
            ),
            FilterChip(
              label: const Text('Show en-route stops (recorded, not flagged)'),
              selected: _showRecorded,
              onSelected: (v) => setState(() => _showRecorded = v),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _loading && _flags == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : flags.isEmpty
                        ? const EmptyState(
                            icon: Icons.speed,
                            title: 'No flags',
                            hint: 'Overspeed and slow stretches need the route\'s speed limits, set '
                                'in Rules & Settings.')
                        : ListView.separated(
                            itemCount: flags.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, i) => _FlagCard(flag: flags[i], onChanged: _load),
                          ),
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag, required this.onChanged});
  final DrivingFlag flag;
  final VoidCallback onChanged;

  static final _time = DateFormat.jm();

  static String kind(String type) => switch (type) {
        'overspeed' => 'Overspeed',
        'slow_stretch' => 'Slow stretch',
        'unscheduled_stop' => 'Unscheduled stop',
        'en_route_stop' => 'En-route stop',
        _ => type,
      };

  String get _what {
    final f = flag;
    String minutes(int s) => s >= 60 ? '${s ~/ 60} min ${s % 60} s' : '$s s';
    return switch (f.type) {
      'overspeed' => '${f.maxSpeed?.toStringAsFixed(0)} km/h against a ${f.limit?.toStringAsFixed(0)} km/h '
          'limit for ${minutes(f.durationS ?? 0)}',
      'slow_stretch' => 'Took ${f.timeRatio?.toStringAsFixed(2)} times the stretch\'s expected time',
      _ => '${f.end == null ? 'Standing, so far ' : 'Stood '}${minutes(f.durationS ?? 0)}, '
          '${f.nearestStopM?.toStringAsFixed(0) ?? '—'} m from the nearest stop',
    };
  }

  @override
  Widget build(BuildContext context) {
    final f = flag;
    final role = context.read<AuthProvider>().profile?.role;
    final manager = role?.isManager ?? false;
    final records = manager || (role?.isCashier ?? false);
    final badge = switch (f.reviewStatus) {
      _ when f.disputeStatus == 'open' => const StatusBadge('Disputed', tone: Tone.warning),
      'reviewed' => const StatusBadge('Reviewed', tone: Tone.info),
      'dismissed' => const StatusBadge('Dismissed'),
      _ => f.flagged
          ? const StatusBadge('Open', tone: Tone.danger)
          : const StatusBadge('Recorded, not flagged'),
    };
    final open = f.flagged && f.reviewStatus == 'open' && f.disputeStatus != 'open';
    return Panel(
      title: '${kind(f.type)} · ${_time.format(f.start)}',
      icon: f.type == 'overspeed' ? Icons.speed : Icons.pause_circle_outline,
      trailing: badge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FactLine(Icons.timeline, _what),
          FactLine(Icons.place_outlined, f.place ?? 'Place not known'),
          FactLine(Icons.directions_bus_outlined, f.tripLabel),
          FactLine(Icons.badge_outlined,
              'Operator ${f.operatorName ?? '—'}, licence ${f.operatorLicence ?? '—'}, plate ${f.plateNumber ?? '—'}'),
          if (f.reviewedAt != null)
            FactLine(Icons.rule, '${f.reviewStatus == 'dismissed' ? 'Dismissed' : 'Reviewed'} by '
                '${f.reviewedBy ?? '—'}, ${_time.format(f.reviewedAt!)}${f.reviewNote != null ? ': ${f.reviewNote}' : ''}'),
          if (open && records) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, children: [
              if (manager) ...[
                FilledButton.tonal(onPressed: () => _review(context), child: const Text('Mark reviewed')),
                OutlinedButton(onPressed: () => _dismiss(context), child: const Text('Dismiss')),
              ],
              TextButton(onPressed: () => _dispute(context), child: const Text('Record operator\'s dispute')),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context) async {
    final oversight = context.read<OversightRepository>();
    final note = await askText(context,
        title: 'Mark the flag reviewed',
        intro: 'You looked at it and it stands. It stays on the trip\'s record.',
        label: 'Note',
        confirmLabel: 'Mark reviewed',
        required: false);
    if (note == null || !context.mounted) return;
    if (await runAction(context, () => oversight.reviewFlag(flag.id, status: 'reviewed', note: note),
        'Flag reviewed.')) {
      onChanged();
    }
  }

  Future<void> _dismiss(BuildContext context) async {
    final oversight = context.read<OversightRepository>();
    final note = await askText(context,
        title: 'Dismiss the flag',
        intro: 'The flag does not stand, for example the van gave way to an ambulance. Say why.',
        label: 'Reason',
        confirmLabel: 'Dismiss');
    if (note == null || !context.mounted) return;
    if (await runAction(context, () => oversight.reviewFlag(flag.id, status: 'dismissed', note: note),
        'Flag dismissed.')) {
      onChanged();
    }
  }

  Future<void> _dispute(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final words = await askText(context,
        title: 'Record the operator\'s dispute',
        intro: '${kind(flag.type)} at ${_time.format(flag.start)}. The Terminal Manager decides it; '
            'the decision reviews the flag.',
        label: 'The operator\'s words',
        confirmLabel: 'Record dispute',
        maxLength: 500);
    if (words == null || !context.mounted) return;
    if (await runAction(context, () => money.disputeFlag(flag.id, words), 'Dispute recorded.')) {
      onChanged();
    }
  }
}
