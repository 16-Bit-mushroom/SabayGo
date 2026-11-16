import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/oversight_repository.dart';
import '../../core/layout/console_router.dart';

/// The Van Status Board (brief 8): every van travelling, on site, not on
/// a trip or out of service, from the trip status and GPS readings already
/// stored. For the Cashier it shows which vans are out and which still owe
/// A2Z's share of their last trip.
class VanBoardScreen extends StatefulWidget {
  const VanBoardScreen({super.key});

  @override
  State<VanBoardScreen> createState() => _VanBoardScreenState();
}

class _VanBoardScreenState extends State<VanBoardScreen> {
  late final OversightRepository _oversight = context.read<OversightRepository>();
  List<VanStatus>? _vans;
  bool _loading = true;
  String? _error;

  /// A quiet refresh failed: the board still shows the last reading, and
  /// says so, rather than passing old positions off as now.
  DateTime? _staleSince;
  Timer? _timer;

  static const _order = ['travelling', 'on_site', 'not_on_trip', 'out_of_service'];

  @override
  void initState() {
    super.initState();
    _load();
    // A display refresh, like the Overview map: the board reads what the
    // phones already sent.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
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
      final vans = await _oversight.vanBoard();
      if (mounted) {
        setState(() {
          _vans = vans;
          _staleSince = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
      if (mounted && quiet) setState(() => _staleSince ??= DateTime.now());
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  static (String, Tone, IconData) state(String s) => switch (s) {
        'travelling' => ('Travelling', Tone.warning, Icons.near_me_outlined),
        'on_site' => ('On site', Tone.success, Icons.local_parking),
        // Red is for alarms; a van being repaired is not one.
        'out_of_service' => ('Out of service', Tone.neutral, Icons.build_outlined),
        _ => ('Not on a trip', Tone.neutral, Icons.remove_circle_outline),
      };

  @override
  Widget build(BuildContext context) {
    final vans = [...?_vans]..sort((a, b) => _order.indexOf(a.state).compareTo(_order.indexOf(b.state)));
    int count(String s) => vans.where((v) => v.state == s).length;
    final owing = vans.where((v) => v.owes > 0).length;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Van Status Board',
            description: 'Where each van is now, from its trips and GPS readings. Refreshes every 15 '
                'seconds.',
            actions: [RefreshButton(onPressed: _load, busy: _loading)],
          ),
          if (_staleSince != null && _error == null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: FactLine(Icons.sync_problem,
                  'Could not refresh since ${DateFormat.jm().format(_staleSince!)}. This is the last reading.',
                  colour: AppColors.warning),
            ),
          if (_vans != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: CardRow(children: [
                // Out of service only when a van is: four figures a row (10 Nov).
                for (final s in _order)
                  if (s != 'out_of_service' || count(s) > 0)
                  StatTile(label: state(s).$1, value: '${count(s)}', icon: state(s).$3,
                      caption: 'of ${vans.length} vans'),
                StatTile(
                    label: 'With a balance', value: '$owing',
                    icon: Icons.money_off, color: owing > 0 ? AppColors.warning : null,
                    caption: 'of ${vans.length} vans, from their last trip'),
              ]),
            ),
          Expanded(
            child: _loading && _vans == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : vans.isEmpty
                        ? const EmptyState(
                            icon: Icons.airport_shuttle_outlined,
                            title: 'No vans yet',
                            hint: 'Vans are added under Setup, Operators & vans.')
                        // A card a van (the owner's reference): three to a
                        // row on a wide screen.
                        : LayoutBuilder(builder: (context, c) {
                            final cols = c.maxWidth >= 1200 ? 3 : (c.maxWidth >= 760 ? 2 : 1);
                            final w = (c.maxWidth - AppSpacing.lg * (cols - 1)) / cols;
                            // Row by row, every card in a row one height
                            // (12 Nov: cards of different heights looked
                            // untidy); a short last row keeps the width.
                            final rows = <Widget>[
                              for (var i = 0; i < vans.length; i += cols)
                                IntrinsicHeight(
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    for (var j = 0; j < cols; j++) ...[
                                      if (j > 0) const SizedBox(width: AppSpacing.lg),
                                      SizedBox(
                                        width: w,
                                        child: i + j < vans.length ? _VanCard(van: vans[i + j]) : null,
                                      ),
                                    ],
                                  ]),
                                ),
                            ];
                            return SingleChildScrollView(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                for (final (k, r) in rows.indexed) ...[if (k > 0) const SizedBox(height: AppSpacing.lg), r],
                              ]),
                            );
                          }),
          ),
        ],
      ),
    );
  }
}

class _VanCard extends StatelessWidget {
  const _VanCard({required this.van});
  final VanStatus van;

  static final _time = DateFormat.jm();

  /// The door camera's count against the van's spaces, or why there is
  /// none -- the same words as the Overview's Live vans.
  static String _count(VanStatus v) {
    final of = v.aboard == null ? null : '${v.aboard} of ${v.seatCapacity} aboard';
    return switch (v.camera) {
      'live' => '$of (camera live)',
      'lens_blocked' => of == null ? 'Camera covered: not counted' : 'Camera covered, last count $of',
      'silent' => of == null ? 'Camera silent: not counted' : 'Camera silent, last count $of',
      'no_phone' => 'No phone: not counted',
      _ => of ?? 'Not counted',
    };
  }

  @override
  Widget build(BuildContext context) {
    final v = van;
    final text = Theme.of(context).textTheme;
    final (label, tone, _) = _VanBoardScreenState.state(v.state);
    final onTrip = v.state == 'travelling' || v.state == 'on_site';
    final trip = onTrip
        ? [
            v.routeName ?? v.tripLabel ?? 'Trip',
            if (v.departure != null) '${v.state == 'travelling' ? 'left' : 'leaves'} ${_time.format(v.departure!)}',
          ].join(', ')
        : (v.state == 'out_of_service'
            ? (v.operationalStatus == 'maintenance' ? 'Under repair' : 'Not in use')
            : 'No trip now');
    Widget row(String k, String value, {Color? colour, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: text.bodySmall)),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: text.bodySmall?.copyWith(
                      color: colour ?? AppColors.textPrimary, fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
            ),
          ]),
        );
    final eligible = v.owes <= 0 && v.state != 'out_of_service';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: v.owes > 0 ? AppColors.warningContainer.withValues(alpha: 0.35) : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: v.owes > 0 ? const Color(0xFFE0B252) : AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(6)),
            child: Text(v.plateNumber,
                style: const TextStyle(color: AppColors.onFill, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
          ),
          const Spacer(),
          StatusBadge(label, tone: tone),
        ]),
        const SizedBox(height: AppSpacing.md),
        Text('Operator: ${v.operatorName}', style: text.titleSmall),
        Text('Licence ${v.operatorLicence}', style: text.bodySmall),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        row('Trip', trip),
        if (onTrip) row('Dispatcher', v.dispatcherName ?? 'Not assigned'),
        if (onTrip) row('Door camera', _count(v)),
        if (v.state == 'travelling')
          row('GPS',
              v.positionAt == null
                  ? 'No reading yet'
                  : '${v.positionStale == true ? 'Last seen' : 'Near'} ${v.nearestStopName ?? 'the route'}, '
                      '${_time.format(v.positionAt!)}',
              colour: v.positionStale == true ? AppColors.danger : null),
        row('Fees balance', peso.format(v.owes > 0 ? v.owes : 0),
            colour: v.owes > 0 ? AppColors.warning : AppColors.primary, strong: true),
        // The footer sits at the bottom, level across a row of cards.
        const Spacer(),
        const SizedBox(height: AppSpacing.sm),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(
            child: Text(
              eligible
                  ? '✓ Can be dispatched'
                  : v.owes > 0
                      ? 'Next assignment waits for the fees'
                      : 'Out of service',
              style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700, color: eligible ? AppColors.primary : AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: () => context.read<ConsoleLocation>().go('/${slug('Trips')}/${slug('Trips')}'),
            child: const Text('Trip sheet'),
          ),
        ]),
      ]),
    );
  }
}
