import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/route_repository.dart';
import 'setup_status.dart';
import 'step_frame.dart';

final _date = DateFormat('d MMM yyyy');

/// Setup, Fares: the LTFRB-approved fare from a route's first stop to each
/// drop-off (brief 2.1, Table 27). A change is dated when it takes effect;
/// trips before that day keep the fare of their own day, and a ticket
/// already sold keeps its price. Fares come from here, never typed in at a
/// van door.
class FaresStep extends StatefulWidget {
  const FaresStep({super.key, required this.onChanged, required this.onOpenStep});
  final VoidCallback onChanged;
  final ValueChanged<SetupStep> onOpenStep;

  @override
  State<FaresStep> createState() => _FaresStepState();
}

class _FaresStepState extends State<FaresStep> {
  late final RouteRepository _network = context.read<RouteRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  List<RouteSummary>? _routes;
  Map<String, List<Fare>> _fares = const {};
  String? _error;
  bool _loading = true;
  String? _selected;

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
      final routes = [for (final r in await _dispatch.listRoutes()) if (r.stops.length > 1) r];
      final fares = await Future.wait([for (final r in routes) _network.fares(r.routeId)]);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _fares = {for (var i = 0; i < routes.length; i++) routes[i].routeId: fares[i]};
        // Open on the first route in service that still lacks a fare.
        _selected ??= (routes.where((r) => r.isActive && _missing(r).isNotEmpty).firstOrNull ??
                routes.where((r) => r.isActive).firstOrNull)
            ?.routeId;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _missing(RouteSummary r) => SetupFacts(fares: _fares).missingFares(r);

  Future<bool> _save(RouteSummary route, Map<int, String> amounts, DateTime from) async {
    final when = DateUtils.isSameDay(from, DateTime.now()) ? 'from today' : 'from ${_date.format(from)}';
    final ok = await runAction(
        context, () => _network.saveFares(route.routeId, amounts, from), 'Fares for ${route.routeName} saved, $when.');
    if (!ok || !mounted) return false;
    await _load();
    widget.onChanged();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes ?? const <RouteSummary>[];
    final selected = routes.where((r) => r.routeId == _selected).firstOrNull;
    return StepFrame(
      title: 'Fares',
      description: 'The fare from the first stop to each drop-off, as LTFRB approved it. '
          'A route cannot be booked to a drop-off that has no fare.',
      actions: [RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading && _routes == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : RecordList(
                  title: 'Routes',
                  empty: EmptyState(
                    icon: Icons.route,
                    title: 'No route to set fares on',
                    hint: 'Fares belong to a route. Enter the route first.',
                  ),
                  rows: [
                    for (final r in routes)
                      RecordRow(
                        leading: Icon(Icons.payments_outlined, color: AppColors.textMuted),
                        title: '${r.routeCode} · ${r.routeName}',
                        subtitle: _summary(r),
                        badges: [
                          if (!r.isActive)
                            const StatusBadge('Out of service')
                          else if (_missing(r).isEmpty)
                            const StatusBadge('Complete', tone: Tone.success)
                          else
                            StatusBadge('${_missing(r).length} missing', tone: Tone.warning),
                        ],
                        selected: r.routeId == _selected,
                        semanticLabel: '${r.routeName} fares. Opens them.',
                        onTap: () => setState(() => _selected = r.routeId),
                      ),
                  ],
                ),
      side: selected == null
          ? (_routes != null && !routes.any((r) => r.isActive)
              ? SidePanel(
                  title: 'Fares',
                  child: BlockedNotice(
                    message: 'Fares are set on a route in service, and there is none yet.',
                    action: 'Go to Route',
                    onAction: () => widget.onOpenStep(SetupStep.route),
                  ),
                )
              : null)
          : SidePanel(
              title: 'Fares · ${selected.routeName}',
              child: FareForm(
                key: ValueKey('${selected.routeId}-${_fares[selected.routeId]?.length}'),
                route: selected,
                fares: _fares[selected.routeId] ?? const [],
                onSave: (amounts, from) => _save(selected, amounts, from),
              ),
            ),
    );
  }

  String _summary(RouteSummary r) {
    final inForce = {
      for (final f in _fares[r.routeId] ?? const <Fare>[])
        if (f.fromStop == 1 && f.status == 'in_force') f.toStop: f
    };
    final parts = [
      for (final s in r.stops.skip(1))
        if (inForce[s.sequence] != null) '${s.name} ${peso.format(inForce[s.sequence]!.amount)}'
    ];
    return parts.isEmpty ? 'No fares yet' : parts.join(' · ');
  }
}

/// The fare from stop 1 on [day]: the latest row dated on or before it, as
/// the server reads it.
Fare? fareOn(List<Fare> fares, int stop, DateTime day) {
  Fare? best;
  for (final f in fares) {
    if (f.fromStop != 1 || f.toStop != stop || f.effectiveFrom.isAfter(day)) continue;
    if (best == null || f.effectiveFrom.isAfter(best.effectiveFrom)) best = f;
  }
  return best;
}

/// The fare from stop 1 to each drop-off, taking effect on a chosen day.
/// Only the fares that differ from those in force on that day are sent.
class FareForm extends StatefulWidget {
  const FareForm({super.key, required this.route, required this.fares, required this.onSave});
  final RouteSummary route;
  final List<Fare> fares;
  final Future<bool> Function(Map<int, String> amounts, DateTime from) onSave;

  @override
  State<FareForm> createState() => _FareFormState();
}

class _FareFormState extends State<FareForm> {
  final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _from = _today;
  late final List<RouteStop> _dropOffs = widget.route.stops.skip(1).toList();
  late final Map<int, TextEditingController> _amounts = {
    for (final s in _dropOffs)
      s.sequence: TextEditingController(text: fareOn(widget.fares, s.sequence, _today)?.amount.toStringAsFixed(2)),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  static final _money = RegExp(r'^\d+(\.\d{1,2})?$');

  /// Drop-off -> amount for every fare that changes on [_from]; null when a
  /// field is not an amount.
  Map<int, String>? get _changes {
    final out = <int, String>{};
    for (final MapEntry(key: stop, value: c) in _amounts.entries) {
      final v = c.text.trim();
      if (v.isEmpty) continue;
      if (!_money.hasMatch(v)) return null;
      final amount = double.parse(v);
      if (amount != fareOn(widget.fares, stop, _from)?.amount) out[stop] = amount.toStringAsFixed(2);
    }
    return out;
  }

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 730)),
      helpText: 'Takes effect on',
    );
    if (day != null) setState(() => _from = day);
  }

  Future<void> _save(bool _) async {
    setState(() => _busy = true);
    await widget.onSave(_changes!, _from);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes;
    final text = Theme.of(context).textTheme;
    final first = widget.route.stops.first;
    final scheduled = [for (final f in widget.fares) if (f.fromStop == 1 && f.status == 'scheduled') f]
      ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    String name(int seq) => widget.route.stops.firstWhere((s) => s.sequence == seq).name;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('From ${first.name}, where every passenger boards. Trips before the day it takes effect keep '
          'the fare of their own day.', style: text.bodySmall),
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        const Text('Takes effect'),
        const SizedBox(width: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _pickDay,
          icon: const Icon(Icons.event, size: 18),
          label: Text(_from == _today ? 'Today, ${_date.format(_from)}' : _date.format(_from)),
        ),
      ]),
      const SizedBox(height: AppSpacing.md),
      for (final s in _dropOffs)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            QueueTile('${s.sequence}'),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  switch (fareOn(widget.fares, s.sequence, _from)) {
                    null => 'No fare on ${_date.format(_from)}',
                    final Fare f => '${peso.format(f.amount)} on ${_date.format(_from)}',
                  },
                  style: text.bodySmall,
                ),
              ]),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _amounts[s.sequence],
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                decoration: const InputDecoration(prefixText: '₱ '),
              ),
            ),
          ]),
        ),
      for (final f in scheduled)
        FactLine(Icons.event_outlined, 'From ${_date.format(f.effectiveFrom)}: ${name(f.toStop)} ${peso.format(f.amount)}',
            colour: AppColors.info),
      if (changes == null) const FormProblem('A fare is an amount in pesos, like 120 or 120.50.'),
      FormButtons(
        adding: false,
        busy: _busy,
        onSave: changes == null || changes.isEmpty ? null : _save,
        saveLabel: changes == null || changes.isEmpty
            ? 'Save fares'
            : 'Save ${changes.length} fare${changes.length == 1 ? '' : 's'}',
      ),
    ]);
  }
}
