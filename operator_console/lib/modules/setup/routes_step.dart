import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/route_repository.dart';
import 'setup_status.dart';
import 'step_frame.dart';

/// Setup, Route: A2Z's LTFRB routes with the stops in order (brief 2.1).
/// Every passenger boards at stop 1. A route's stops are fixed once it is
/// saved, because bookings and fares are numbered by them: a route that
/// changes is taken out of service and entered again.
class RoutesStep extends StatefulWidget {
  const RoutesStep({super.key, required this.onChanged, required this.onOpenStep});
  final VoidCallback onChanged;
  final ValueChanged<SetupStep> onOpenStep;

  @override
  State<RoutesStep> createState() => _RoutesStepState();
}

class _RoutesStepState extends State<RoutesStep> {
  late final RouteRepository _network = context.read<RouteRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  List<RouteSummary>? _routes;
  List<Terminal> _terminals = const [];
  String? _error;
  bool _loading = true;
  String? _selected;
  int _blank = 0;

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
      final r = await Future.wait([_dispatch.listRoutes(), _network.terminals()]);
      if (!mounted) return;
      setState(() {
        _routes = r[0] as List<RouteSummary>;
        _terminals = [for (final t in r[1] as List<Terminal>) if (t.isActive) t];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _add(NewRoute r, bool another) async {
    final ok = await runAction(
        context,
        () => _network.addRoute(code: r.code, name: r.name, ltfrbCaseNo: r.ltfrbCaseNo, stops: r.stops),
        '${r.name} added. Set its fares next: until then passengers cannot book it.');
    if (!ok || !mounted) return false;
    await _load();
    widget.onChanged();
    if (mounted) {
      setState(() {
        if (another) {
          _selected = null;
          _blank++;
        } else {
          _selected = _routes?.where((x) => x.routeCode == r.code).firstOrNull?.routeId;
        }
      });
    }
    return true;
  }

  Future<bool> _edit(RouteSummary route, (String, String, bool) r) async {
    final ok = await runAction(
        context,
        () => _network.editRoute(route.routeId, name: r.$1, ltfrbCaseNo: r.$2, isActive: r.$3),
        '${r.$1} saved.');
    if (!ok || !mounted) return false;
    await _load();
    widget.onChanged();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes ?? const <RouteSummary>[];
    final selected = routes.where((r) => r.routeId == _selected).firstOrNull;
    final Widget side;
    if (selected != null) {
      side = SidePanel(
        title: '${selected.routeCode} · ${selected.routeName}',
        onClose: () => setState(() => _selected = null),
        closeLabel: 'Back to adding',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StopLine(stops: selected.stops),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => widget.onOpenStep(SetupStep.fares),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Set its fares'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          RouteEditForm(key: ValueKey(selected.routeId), route: selected, onSave: (r) => _edit(selected, r)),
        ]),
      );
    } else if (_routes != null && _terminals.length < 2) {
      side = SidePanel(
        title: 'Add route',
        child: BlockedNotice(
          message: 'A route needs two open terminals; there ${_terminals.length == 1 ? 'is 1' : 'are ${_terminals.length}'}.',
          action: 'Go to Terminals',
          onAction: () => widget.onOpenStep(SetupStep.terminals),
        ),
      );
    } else {
      side = SidePanel(
        title: 'Add route',
        child: RouteForm(key: ValueKey('new-$_blank'), terminals: _terminals, onSave: _add),
      );
    }
    return StepFrame(
      title: 'Route',
      description: 'Each LTFRB route with its stops in order. Passengers board only at the first stop, '
          'and the stops cannot change once the route is saved.',
      actions: [RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading && _routes == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : RecordList(
                  title: 'Routes',
                  addLabel: 'Add route',
                  onAdd: selected == null ? null : () => setState(() => _selected = null),
                  empty: const EmptyState(
                    icon: Icons.route,
                    title: 'No routes yet',
                    hint: 'Enter the route with the form: its code, its name and its stops in order.',
                  ),
                  rows: [
                    for (final r in routes)
                      RecordRow(
                        leading: Icon(Icons.route, color: AppColors.textMuted),
                        title: '${r.routeCode} · ${r.routeName}',
                        subtitle: r.stops.map((s) => s.name).join(' → '),
                        badges: [
                          r.isActive
                              ? const StatusBadge('In service', tone: Tone.success)
                              : const StatusBadge('Out of service'),
                        ],
                        selected: r.routeId == _selected,
                        semanticLabel: '${r.routeName}, ${r.isActive ? 'in service' : 'out of service'}. Opens it.',
                        onTap: () => setState(() => _selected = r.routeId),
                      ),
                  ],
                ),
      side: side,
    );
  }
}

/// A route's stops in order, drawn as the pila: numbered tiles down a
/// column, stop 1 marked as where every passenger boards.
class StopLine extends StatelessWidget {
  const StopLine({super.key, required this.stops});
  final List<RouteStop> stops;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in stops)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(children: [
            QueueTile('${s.sequence}', filled: s.sequence == 1),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(s.name, style: text.bodyMedium)),
            Text(s.sequence == 1 ? 'Boarding' : '${s.offsetMinutes} min',
                style: text.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
    ]);
  }
}

typedef NewRoute = ({String code, String name, String ltfrbCaseNo, List<(String, int)> stops});

/// A new route and its stops in order. The stops cannot change once it is
/// saved, so the form says so before Save.
class RouteForm extends StatefulWidget {
  const RouteForm({super.key, required this.terminals, required this.onSave});
  final List<Terminal> terminals;
  final Future<bool> Function(NewRoute route, bool another) onSave;

  @override
  State<RouteForm> createState() => _RouteFormState();
}

class _RouteFormState extends State<RouteForm> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _ltfrb = TextEditingController();
  final List<String?> _stops = [null, null];
  // Minutes after departure; stop 1 is the departure and has none.
  final List<TextEditingController> _minutes = [TextEditingController(text: '0'), TextEditingController()];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _ltfrb, ..._minutes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_code.text.trim().length < 2 || _name.text.trim().length < 2) return 'Give the route a code and a name.';
    if (_stops.contains(null)) return 'Choose a terminal for every stop.';
    if (_stops.toSet().length != _stops.length) return 'A terminal appears only once on a route.';
    final minutes = [for (final c in _minutes) int.tryParse(c.text.trim())];
    if (minutes.any((m) => m == null || m < 0)) return 'Give the minutes after departure for every stop.';
    for (var i = 1; i < minutes.length; i++) {
      if (minutes[i]! < minutes[i - 1]!) return 'Each stop is reached no earlier than the one before it.';
    }
    return null;
  }

  Future<void> _save(bool another) async {
    setState(() => _busy = true);
    await widget.onSave((
      code: _code.text.trim(),
      name: _name.text.trim(),
      ltfrbCaseNo: _ltfrb.text.trim(),
      stops: [for (var i = 0; i < _stops.length; i++) (_stops[i]!, int.parse(_minutes[i].text.trim()))],
    ), another);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SizedBox(
          width: 120,
          child: TextField(
            controller: _code,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Code', hintText: 'DVO-TAG'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Davao – Tagum'),
          ),
        ),
      ]),
      const SizedBox(height: AppSpacing.md),
      TextField(controller: _ltfrb, decoration: const InputDecoration(labelText: 'LTFRB case number (optional)')),
      const SizedBox(height: AppSpacing.lg),
      Text('Stops, in order', style: text.titleSmall),
      Text('Every passenger boards at stop 1. The stops cannot change once the route is saved.',
          style: text.bodySmall),
      const SizedBox(height: AppSpacing.md),
      for (var i = 0; i < _stops.length; i++)
        Padding(
          // Keyed by the row's own controller, so removing a stop does not
          // hand its terminal to the row below.
          key: ObjectKey(_minutes[i]),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            QueueTile('${i + 1}', filled: i == 0),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _stops[i],
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Terminal'),
                // A long name wraps in the list, spaced so the names do not
                // run together, and shows on one line once picked.
                selectedItemBuilder: (_) => [
                  for (final t in widget.terminals) Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                items: [
                  for (final t in widget.terminals)
                    DropdownMenuItem(
                      value: t.terminalId,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Text(t.name),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _stops[i] = v),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 100,
              child: i == 0
                  ? Text('Boarding', style: text.bodySmall)
                  : TextField(
                      controller: _minutes[i],
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                    ),
            ),
            IconButton(
              tooltip: 'Remove this stop',
              onPressed: i == 0 || _stops.length <= 2 ? null : () => setState(() {
                _stops.removeAt(i);
                _minutes.removeAt(i).dispose();
              }),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _stops.length >= widget.terminals.length
              ? null
              : () => setState(() {
                    _stops.add(null);
                    _minutes.add(TextEditingController());
                  }),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add stop'),
        ),
      ),
      if (problem != null) FormProblem(problem),
      FormButtons(adding: true, busy: _busy, onSave: problem == null ? _save : null, saveLabel: 'Save route'),
    ]);
  }
}

/// Rename a route, record its LTFRB case, or take it out of service.
class RouteEditForm extends StatefulWidget {
  const RouteEditForm({super.key, required this.route, required this.onSave});
  final RouteSummary route;
  final Future<bool> Function((String, String, bool) changes) onSave;

  @override
  State<RouteEditForm> createState() => _RouteEditFormState();
}

class _RouteEditFormState extends State<RouteEditForm> {
  late final _name = TextEditingController(text: widget.route.routeName);
  late final _ltfrb = TextEditingController(text: widget.route.ltfrbCaseNo);
  late bool _active = widget.route.isActive;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ltfrb.dispose();
    super.dispose();
  }

  Future<void> _save(bool _) async {
    setState(() => _busy = true);
    await widget.onSave((_name.text.trim(), _ltfrb.text.trim(), _active));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _name,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(controller: _ltfrb, decoration: const InputDecoration(labelText: 'LTFRB case number (optional)')),
      const SizedBox(height: AppSpacing.sm),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('In service'),
        subtitle: const Text('Out of service: passengers no longer find it and the timetable makes no '
            'trips on it. Trips already made keep their bookings; void them on Trips if they will not run.'),
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
      FormButtons(adding: false, busy: _busy, onSave: _name.text.trim().length < 2 ? null : _save),
    ]);
  }
}
