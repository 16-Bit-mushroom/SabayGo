import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/oversight_repository.dart';
import '../setup/step_frame.dart';

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
              child: Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                for (final s in _order)
                  SizedBox(width: 170, child: StatTile(
                      label: state(s).$1, value: '${count(s)}', icon: state(s).$3)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Owe A2Z\'s share', value: '$owing',
                    icon: Icons.money_off, color: owing > 0 ? AppColors.warning : null,
                    caption: 'From their last trip')),
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
                        : Panel(
                            fill: true,
                            child: Column(children: [
                              const _VanRow.heads(),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: vans.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (_, i) => _VanRow(van: vans[i]),
                                ),
                              ),
                            ]),
                          ),
          ),
        ],
      ),
    );
  }
}

class _VanRow extends StatelessWidget {
  const _VanRow({required VanStatus this.van});

  /// The column heads, in the row's own widths.
  const _VanRow.heads() : van = null;

  final VanStatus? van;

  static Widget _cols(List<Widget> c) => Row(children: [
        SizedBox(width: 110, child: c[0]),
        SizedBox(width: 140, child: c[1]),
        SizedBox(width: 220, child: c[2]),
        Expanded(child: c[3]),
        SizedBox(width: 170, child: Align(alignment: Alignment.centerRight, child: c[4])),
      ]);

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = van;
    if (v == null) {
      final head = text.labelMedium;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _cols([
          Text('Van', style: head),
          Text('Status', style: head),
          Text('Operator', style: head),
          Text('Where and with whom', style: head),
          Text('A2Z\'s share', style: head),
        ]),
      );
    }
    final (label, tone, _) = _VanBoardScreenState.state(v.state);
    final where = switch (v.state) {
      'travelling' => [
          v.routeName ?? '',
          'Dispatcher ${v.dispatcherName ?? 'none'}',
          v.aboard == null ? 'aboard not counted (no phone)' : '${v.aboard} aboard',
          v.positionAt == null
              ? 'no GPS reading yet'
              : '${v.positionStale == true ? 'last seen' : 'near'} ${v.nearestStopName ?? 'the route'} '
                  'at ${_time.format(v.positionAt!)}',
        ].join(' · '),
      'on_site' => '${v.tripLabel ?? ''} · ${v.tripStatus == 'boarding' ? 'boarding' : 'scheduled'}'
          ' · Dispatcher ${v.dispatcherName ?? 'not assigned'}',
      'out_of_service' => v.operationalStatus == 'maintenance' ? 'Under repair' : 'Not in use',
      _ => 'No trip today',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: _cols([
        Align(alignment: Alignment.centerLeft, child: PlateTag(v.plateNumber)),
        Align(alignment: Alignment.centerLeft, child: StatusBadge(label, tone: tone)),
        Text('${v.operatorName}\n${v.operatorLicence}', style: text.bodySmall),
        Text(where, style: text.bodyMedium),
        v.owes > 0
            ? StatusBadge('Owes ${peso.format(v.owes)}', tone: Tone.warning)
            : Text('Nothing owed', style: text.bodySmall),
      ]),
    );
  }
}
