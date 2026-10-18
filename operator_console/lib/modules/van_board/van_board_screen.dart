import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/oversight_repository.dart';

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
      if (mounted) setState(() => _vans = vans);
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  static (String, Tone, IconData) state(String s) => switch (s) {
        'travelling' => ('Travelling', Tone.warning, Icons.near_me_outlined),
        'on_site' => ('On site', Tone.success, Icons.local_parking),
        'out_of_service' => ('Out of service', Tone.danger, Icons.build_outlined),
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
          if (_vans != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                for (final s in _order)
                  SizedBox(width: 170, child: StatTile(
                      label: state(s).$1, value: '${count(s)}', icon: state(s).$3)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Owe A2Z\'s share', value: '$owing',
                    icon: Icons.money_off, color: owing > 0 ? AppColors.danger : null,
                    caption: 'From their last trip')),
              ]),
            ),
          Expanded(
            child: _loading && _vans == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : vans.isEmpty
                        ? const EmptyState(icon: Icons.airport_shuttle_outlined, title: 'No vans yet')
                        : Panel(
                            fill: true,
                            child: ListView.separated(
                              itemCount: vans.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) => _VanRow(van: vans[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _VanRow extends StatelessWidget {
  const _VanRow({required this.van});
  final VanStatus van;

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final v = van;
    final text = Theme.of(context).textTheme;
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
      child: Row(children: [
        SizedBox(width: 110, child: Text(v.plateNumber, style: text.titleSmall)),
        SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: StatusBadge(label, tone: tone))),
        SizedBox(
          width: 220,
          child: Text('${v.operatorName}\n${v.operatorLicence}', style: text.bodySmall),
        ),
        Expanded(child: Text(where, style: text.bodyMedium)),
        SizedBox(
          width: 170,
          child: Align(
            alignment: Alignment.centerRight,
            child: v.owes > 0
                ? StatusBadge('Owes ${peso.format(v.owes)}', tone: Tone.danger)
                : Text('Nothing owed', style: text.bodySmall),
          ),
        ),
      ]),
    );
  }
}
