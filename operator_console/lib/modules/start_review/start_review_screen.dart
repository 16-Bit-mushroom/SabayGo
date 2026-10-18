import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../trip_monitor/trip_lifecycle_panel.dart';

/// Review Automatic Starts (brief 9): the Terminal Manager's list of the
/// day's trips that need a person's look -- a start the system made
/// (held off the statement until reviewed), a trip that left before
/// A2Z's share was recorded, one that departed with more aboard than
/// listed, and one that went Unaudited. The selected trip's Start and
/// departure panel holds the actions: review the start, change the van.
class StartReviewScreen extends StatefulWidget {
  const StartReviewScreen({super.key});

  @override
  State<StartReviewScreen> createState() => _StartReviewScreenState();
}

class _StartReviewScreenState extends State<StartReviewScreen> {
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final OversightRepository _oversight = context.read<OversightRepository>();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<(TripBoardEntry, List<String>)>? _trips;
  Map<String, String> _departedWithMore = const {};
  String? _selected;
  bool _loading = true;
  String? _error;

  static final _time = DateFormat.jm();

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
      final board = await _dispatch.tripBoard(_day);
      final audits = await _oversight.boardingAudit(isoDay(_day));
      final more = {for (final a in audits) if (a.departedWithMore != null) a.tripId: a.departedWithMore!};
      final trips = <(TripBoardEntry, List<String>)>[];
      for (final t in board) {
        final reasons = [
          if (t.awaitsReview) 'Started by the system',
          if (t.paymentStatus == 'left_unpaid') 'Left unpaid',
          if (more.containsKey(t.tripId)) 'More aboard than listed',
          if (t.auditStatus == 'unaudited') 'Unaudited',
        ];
        if (reasons.isNotEmpty) trips.add((t, reasons));
      }
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _departedWithMore = more;
        if (!trips.any((e) => e.$1.tripId == _selected)) {
          _selected = trips.isEmpty ? null : trips.first.$1.tripId;
        }
      });
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
    final trips = _trips ?? const [];
    final selected = trips.where((e) => e.$1.tripId == _selected).firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Review Starts',
            technicalNote: 'StartReviewStatus · HeldShare · AuditStatus',
            description: 'Trips that need your look: started by the system, left before A2Z\'s share '
                'was recorded, departed with more aboard than listed, or went without camera evidence.',
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
                        ? const EmptyState(icon: Icons.task_alt, title: 'Nothing to review on this day')
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 420,
                                child: Panel(
                                  title: 'Trips to review (${trips.length})',
                                  icon: Icons.rule,
                                  fill: true,
                                  child: ListView(children: [
                                    for (final (t, reasons) in trips)
                                      ListTile(
                                        selected: t.tripId == _selected,
                                        onTap: () => setState(() => _selected = t.tripId),
                                        title: Text('${_time.format(t.departureDatetime)} · ${t.routeName}'),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                                          child: Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                                            Text(t.plateNumber ?? 'no van'),
                                            for (final r in reasons)
                                              StatusBadge(r, tone: r == 'Started by the system'
                                                  ? Tone.warning
                                                  : Tone.danger),
                                          ]),
                                        ),
                                      ),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: selected == null
                                    ? const SizedBox.shrink()
                                    : ListView(children: [
                                        if (_departedWithMore[selected.$1.tripId] case final more?)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                            child: Panel(
                                              title: 'Departed with more aboard than listed',
                                              icon: Icons.warning_amber_rounded,
                                              child: Text('$more See Boarding Audit for each boarding.'),
                                            ),
                                          ),
                                        TripLifecyclePanel(trip: selected.$1, onChanged: _load),
                                      ]),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
