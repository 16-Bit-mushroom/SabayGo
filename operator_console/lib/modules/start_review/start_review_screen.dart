import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../trip_monitor/screens/trip_monitor_screen.dart';

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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Live: a start the system makes, or a van leaving unpaid, shows up
    // without a refresh.
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

  /// The trip's full panel from the right: its facts and the Terminal
  /// Manager's steps (review the start, lift the block, change van, void).
  /// The trip in the console's one trip panel (12 Nov: the owner's
  /// screenshot of this page's own panel, one small card above an empty
  /// column). The same panel as Trips: the door camera's count against the
  /// list, the van and Dispatcher, the fees, the passenger list, then the
  /// review itself -- Confirm the start, Change van -- under "More on this
  /// trip". Its figures load as it opens and refresh every 15 s.
  Future<void> _open(TripBoardEntry trip) => showTripDetail(
        context,
        trip: trip,
        day: _day,
        money: null,
        roster: null,
        isManager: true,
        isCashier: false,
        onChanged: () => _load(quiet: true),
      );

  @override
  Widget build(BuildContext context) {
    final trips = _trips ?? const [];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Review Starts',
            description: 'Trips that need your look: started by the system, left before its terminal fees '
                'were recorded, departed with more aboard than listed, or went without camera evidence. '
                'Updates every 30 seconds.',
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
                            icon: Icons.task_alt,
                            title: 'Nothing to review on this day',
                            hint: 'A trip the system started, one that left unpaid, one with more aboard than '
                                'listed or one without camera evidence appears here.')
                        : ListView.separated(
                            itemCount: trips.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, i) => _ReviewCard(
                              trip: trips[i].$1,
                              reasons: trips[i].$2,
                              more: _departedWithMore[trips[i].$1.tripId],
                              onOpen: () => _open(trips[i].$1),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// One trip to review, as the reference's row card: why it is here (one
/// pill a reason), which van and when, what happened in a sentence, and
/// Review on the right.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.trip, required this.reasons, required this.more, required this.onOpen});
  final TripBoardEntry trip;
  final List<String> reasons;
  final String? more;
  final VoidCallback onOpen;

  static final _time = DateFormat.jm();

  static String _unaudited(String? reason) => switch (reason) {
        'no_phone' => 'no phone was out with the van',
        'silent_at_start' => 'the phone was silent at the start',
        'lost_en_route' => 'the phone went silent on the road',
        'lens_blocked' => 'the camera was covered',
        _ => 'no camera evidence',
      };

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final text = Theme.of(context).textTheme;
    final lines = [
      if (t.awaitsReview)
        'Started by the system${t.startedAt == null ? '' : ' at ${_time.format(t.startedAt!)}'}: nobody started it '
            'in time. Left off the daily statement until you review it.',
      if (t.paymentStatus == 'left_unpaid')
        'Left before its terminal fees were recorded. They stay on the van\'s balance, and its next '
            'assignment waits until they are paid.',
      ?more,
      if (t.auditStatus == 'unaudited') 'Unaudited: ${_unaudited(t.unauditedReason)}. Only the passenger list counts.',
    ];
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
        for (final r in reasons)
          StatusBadge(r, tone: r == 'Started by the system' ? Tone.warning : Tone.danger),
      ]),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '${t.plateNumber ?? 'No van'}${t.operatorName == null ? '' : ' (${t.operatorName})'}'
        ' · ${_time.format(t.departureDatetime)} · ${t.routeName}',
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: AppSpacing.sm),
      // The problem itself, at reading size (12 Nov: it was small grey
      // subtext, and the reason a trip is here is the point of the card).
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.error_outline, size: 18, color: AppColors.warning),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(l,
                  style: text.bodyLarge?.copyWith(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w500, height: 1.4)),
            ),
          ]),
        ),
    ]);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 700
            ? Row(children: [
                Expanded(child: details),
                const SizedBox(width: AppSpacing.lg),
                FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.rule, size: 18), label: const Text('Review')),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                details,
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.rule, size: 18), label: const Text('Review')),
              ]),
      ),
    );
  }
}
