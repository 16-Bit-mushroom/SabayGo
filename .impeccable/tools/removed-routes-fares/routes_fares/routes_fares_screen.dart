import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/route_repository.dart';

final _date = DateFormat('d MMM yyyy');

/// Routes & Fares: A2Z's terminals, its LTFRB routes with their stops in
/// order, and the fare from the starting terminal to each drop-off (brief
/// 2.1, Table 27). Every passenger boards at a route's first stop, so a
/// route has one fare per drop-off. A fare change is dated when it takes
/// effect; trips before that date keep the fare of their own day. A
/// route's stops are fixed once it is saved, because bookings and fares are
/// numbered by them: a route that changes is taken out of service and
/// entered again.
class RoutesFaresScreen extends StatefulWidget {
  const RoutesFaresScreen({super.key});

  @override
  State<RoutesFaresScreen> createState() => _RoutesFaresScreenState();
}

class _RoutesFaresScreenState extends State<RoutesFaresScreen> {
  late final RouteRepository _network = context.read<RouteRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  List<RouteSummary>? _routes;
  Map<String, List<Fare>> _fares = const {};
  List<Terminal>? _terminals;
  String _list = 'routes';
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
      final r = await Future.wait([_dispatch.listRoutes(), _network.terminals()]);
      final routes = r[0] as List<RouteSummary>;
      final terminals = r[1] as List<Terminal>;
      final fares = await Future.wait([for (final r in routes) _network.fares(r.routeId)]);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _terminals = terminals;
        _fares = {for (var i = 0; i < routes.length; i++) routes[i].routeId: fares[i]};
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Terminal> get _open => [for (final t in _terminals ?? const <Terminal>[]) if (t.isActive) t];

  @override
  Widget build(BuildContext context) {
    final routes = _routes ?? const <RouteSummary>[];
    final terminals = _terminals ?? const <Terminal>[];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Routes & Fares',
            technicalNote: 'Terminals · Routes · Route_Stops · Fare_Matrix',
            description: 'A2Z\'s terminals, its LTFRB routes with the stops in order, and the fare from '
                'the starting terminal to each drop-off. Passengers board only at a route\'s first stop.',
            actions: [
              OutlinedButton.icon(
                onPressed: _terminals == null ? null : _addTerminal,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add terminal'),
              ),
              FilledButton.icon(
                onPressed: _open.length < 2 ? null : _addRoute,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add route'),
              ),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'routes', label: Text('Routes (${routes.length})')),
              ButtonSegment(value: 'terminals', label: Text('Terminals (${terminals.length})')),
            ],
            selected: {_list},
            onSelectionChanged: (s) => setState(() => _list = s.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _loading && _routes == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : _list == 'routes'
                        ? _routeList(routes)
                        : _terminalList(terminals),
          ),
        ],
      ),
    );
  }

  Widget _routeList(List<RouteSummary> routes) {
    if (routes.isEmpty) {
      return const EmptyState(
          icon: Icons.route,
          title: 'No routes yet',
          hint: 'Add the terminals first, then each LTFRB route with its stops in order.');
    }
    return ListView.separated(
      itemCount: routes.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => _RouteCard(
        route: routes[i],
        fares: _fares[routes[i].routeId] ?? const [],
        onFares: () => _setFares(routes[i]),
        onEdit: () => _editRoute(routes[i]),
      ),
    );
  }

  Widget _terminalList(List<Terminal> terminals) {
    if (terminals.isEmpty) {
      return const EmptyState(
          icon: Icons.location_on_outlined,
          title: 'No terminals yet',
          hint: 'Add each terminal where vans load or passengers alight.');
    }
    return ListView.separated(
      itemCount: terminals.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => _TerminalCard(terminal: terminals[i], onEdit: () => _editTerminal(terminals[i])),
    );
  }

  Future<void> _addTerminal() async {
    final draft = await showDialog<TerminalDraft>(context: context, builder: (_) => const _TerminalDialog());
    if (draft == null || !mounted) return;
    if (await runAction(context, () => _network.addTerminal(draft), '${draft.name} added.')) _load();
  }

  Future<void> _editTerminal(Terminal t) async {
    final draft = await showDialog<TerminalDraft>(context: context, builder: (_) => _TerminalDialog(terminal: t));
    if (draft == null || !mounted) return;
    if (await runAction(context, () => _network.editTerminal(t.terminalId, draft), '${draft.name} saved.')) _load();
  }

  Future<void> _addRoute() async {
    final r = await showDialog<_NewRoute>(context: context, builder: (_) => _AddRouteDialog(terminals: _open));
    if (r == null || !mounted) return;
    final ok = await runAction(
        context,
        () => _network.addRoute(code: r.code, name: r.name, ltfrbCaseNo: r.ltfrbCaseNo, stops: r.stops),
        '${r.name} added. Set its fares next: until then passengers cannot book it.');
    if (ok) _load();
  }

  Future<void> _editRoute(RouteSummary route) async {
    final r = await showDialog<(String, String, bool)>(context: context, builder: (_) => _EditRouteDialog(route: route));
    if (r == null || !mounted) return;
    final ok = await runAction(
        context,
        () => _network.editRoute(route.routeId, name: r.$1, ltfrbCaseNo: r.$2, isActive: r.$3),
        '${r.$1} saved.');
    if (ok) _load();
  }

  Future<void> _setFares(RouteSummary route) async {
    final r = await showDialog<(Map<int, String>, DateTime)>(
        context: context, builder: (_) => _FaresDialog(route: route, fares: _fares[route.routeId] ?? const []));
    if (r == null || !mounted) return;
    final when = DateUtils.isSameDay(r.$2, DateTime.now()) ? 'from today' : 'from ${_date.format(r.$2)}';
    if (await runAction(context, () => _network.saveFares(route.routeId, r.$1, r.$2),
        'Fares for ${route.routeName} saved, $when.')) {
      _load();
    }
  }
}

/// The fare from stop 1 to [stop] on [day]: the latest row dated on or
/// before it, as the server reads it.
Fare? _fareOn(List<Fare> fares, int stop, DateTime day) {
  Fare? best;
  for (final f in fares) {
    if (f.fromStop != 1 || f.toStop != stop || f.effectiveFrom.isAfter(day)) continue;
    if (best == null || f.effectiveFrom.isAfter(best.effectiveFrom)) best = f;
  }
  return best;
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.fares, required this.onFares, required this.onEdit});
  final RouteSummary route;
  final List<Fare> fares;
  final VoidCallback onFares;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final first = r.stops.isEmpty ? null : r.stops.first;
    final dropOffs = r.stops.skip(1).toList();
    final inForce = {for (final f in fares) if (f.fromStop == 1 && f.status == 'in_force') f.toStop: f};
    final missing = [for (final s in dropOffs) if (!inForce.containsKey(s.sequence)) s.name];
    final scheduled = [for (final f in fares) if (f.fromStop == 1 && f.status == 'scheduled') f]
      ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    String name(int seq) => r.stops.firstWhere((s) => s.sequence == seq).name;
    return Panel(
      title: '${r.routeCode} · ${r.routeName}',
      icon: Icons.route,
      trailing: r.isActive
          ? const StatusBadge('In service', tone: Tone.success)
          : const StatusBadge('Out of service'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FactLine(Icons.linear_scale, [
          for (final s in r.stops) s.sequence == 1 ? s.name : '${s.name} (${s.offsetMinutes} min)'
        ].join('  →  ')),
        FactLine(Icons.gavel_outlined,
            r.ltfrbCaseNo == null ? 'No LTFRB case number recorded' : 'LTFRB case ${r.ltfrbCaseNo}'),
        if (first != null && inForce.isNotEmpty)
          FactLine(Icons.payments_outlined, 'Fares from ${first.name}: ${[
            for (final s in dropOffs)
              if (inForce[s.sequence] != null) '${s.name} ${peso.format(inForce[s.sequence]!.amount)}'
          ].join(' · ')}'),
        if (missing.isNotEmpty)
          FactLine(Icons.warning_amber_outlined,
              'No fare to ${missing.join(', ')}: passengers cannot book ${missing.length == 1 ? 'it' : 'them'}.',
              colour: AppColors.warning),
        for (final f in scheduled)
          FactLine(Icons.event_outlined,
              'From ${_date.format(f.effectiveFrom)}: ${name(f.toStop)} ${peso.format(f.amount)}',
              colour: AppColors.info),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, children: [
          FilledButton.tonalIcon(
            onPressed: dropOffs.isEmpty ? null : onFares,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Set fares'),
          ),
          OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
        ]),
      ]),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.terminal, required this.onEdit});
  final Terminal terminal;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = terminal;
    return Panel(
      title: '${t.name} · ${t.city}',
      icon: Icons.location_on_outlined,
      trailing: t.isActive ? const StatusBadge('Open', tone: Tone.success) : const StatusBadge('Closed'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (t.address != null) FactLine(Icons.signpost_outlined, t.address!),
        FactLine(Icons.my_location,
            '${t.latitude.toStringAsFixed(6)}, ${t.longitude.toStringAsFixed(6)} · '
            '${t.geofenceM == null ? 'default terminal zone' : 'terminal zone ${t.geofenceM} m'} · '
            '${t.isStaffed ? 'staffed' : 'not staffed'}'),
        FactLine(Icons.route,
            t.routes.isEmpty ? 'On no route in service' : 'On ${t.routes.join(', ')}'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
      ]),
    );
  }
}

/// Add a terminal, or correct or close one. A terminal on a route in
/// service cannot close (the server says which routes).
class _TerminalDialog extends StatefulWidget {
  const _TerminalDialog({this.terminal});
  final Terminal? terminal;

  @override
  State<_TerminalDialog> createState() => _TerminalDialogState();
}

class _TerminalDialogState extends State<_TerminalDialog> {
  Terminal? get _t => widget.terminal;
  late final _name = TextEditingController(text: _t?.name);
  late final _city = TextEditingController(text: _t?.city);
  late final _address = TextEditingController(text: _t?.address);
  late final _lat = TextEditingController(text: _t?.latitude.toString());
  late final _lng = TextEditingController(text: _t?.longitude.toString());
  late final _zone = TextEditingController(text: _t?.geofenceM?.toString());
  late bool _staffed = _t?.isStaffed ?? true;
  late bool _open = _t?.isActive ?? true;

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _lat, _lng, _zone]) {
      c.dispose();
    }
    super.dispose();
  }

  /// What is wrong with the form, or null when it can be saved.
  String? get _problem {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final zone = _zone.text.trim();
    if (_name.text.trim().length < 2 || _city.text.trim().length < 2) return 'Give the terminal\'s name and city.';
    if (lat == null || lat < -90 || lat > 90) return 'Latitude is a number between -90 and 90.';
    if (lng == null || lng < -180 || lng > 180) return 'Longitude is a number between -180 and 180.';
    final m = int.tryParse(zone);
    if (zone.isNotEmpty && (m == null || m < 25 || m > 2000)) return 'The terminal zone is 25 to 2000 m.';
    return null;
  }

  bool get _moved {
    final t = _t;
    return t != null &&
        (double.tryParse(_lat.text.trim()) != t.latitude || double.tryParse(_lng.text.trim()) != t.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final t = _t;
    Widget field(TextEditingController c, String label, {String? hint, bool number = false}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        );
    return AlertDialog(
      title: Text(t == null ? 'Add a terminal' : 'Edit ${t.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            field(_name, 'Name', hint: 'Ecoland Terminal'),
            field(_city, 'City', hint: 'Davao City'),
            field(_address, 'Address (optional)'),
            Row(children: [
              Expanded(child: field(_lat, 'Latitude', hint: '7.0503', number: true)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: field(_lng, 'Longitude', hint: '125.5947', number: true)),
            ]),
            field(_zone, 'Terminal zone radius in metres (optional)',
                hint: 'Empty: the default zone in Rules & Settings', number: true),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Staffed'),
              subtitle: const Text('A2Z has a Dispatcher or office here.'),
              value: _staffed,
              onChanged: (v) => setState(() => _staffed = v),
            ),
            if (t != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open'),
                subtitle: const Text('Closes only while no route in service stops here.'),
                value: _open,
                onChanged: (v) => setState(() => _open = v),
              ),
            if (_moved)
              const FactLine(Icons.info_outline,
                  'Moving the terminal re-measures the speed-limit stretches of the routes through it.'),
            if (problem != null) Text(problem, style: TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.pop(
                    context,
                    TerminalDraft(
                      name: _name.text.trim(),
                      city: _city.text.trim(),
                      address: _address.text.trim(),
                      latitude: double.parse(_lat.text.trim()),
                      longitude: double.parse(_lng.text.trim()),
                      geofenceM: int.tryParse(_zone.text.trim()),
                      isStaffed: _staffed,
                      isActive: _open,
                    )),
          child: Text(t == null ? 'Add terminal' : 'Save'),
        ),
      ],
    );
  }
}

typedef _NewRoute = ({String code, String name, String ltfrbCaseNo, List<(String, int)> stops});

/// A new route and its stops in order. The stops cannot change once it is
/// saved, so the dialog says so before Save.
class _AddRouteDialog extends StatefulWidget {
  const _AddRouteDialog({required this.terminals});
  final List<Terminal> terminals;

  @override
  State<_AddRouteDialog> createState() => _AddRouteDialogState();
}

class _AddRouteDialogState extends State<_AddRouteDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _ltfrb = TextEditingController();
  final List<String?> _stops = [null, null];
  // Minutes after departure; stop 1 is the departure and has none.
  final List<TextEditingController> _minutes = [TextEditingController(text: '0'), TextEditingController()];

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

  void _addStop() => setState(() {
        _stops.add(null);
        _minutes.add(TextEditingController());
      });

  void _removeStop(int i) => setState(() {
        _stops.removeAt(i);
        _minutes.removeAt(i).dispose();
      });

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Add a route'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                width: 160,
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
            Text('Every passenger boards at stop 1. The stops cannot change once the route is saved: '
                'bookings and fares are numbered by them.', style: text.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < _stops.length; i++)
              Padding(
                // Keyed by the row's own controller, so removing a stop does
                // not hand its terminal to the row below.
                key: ObjectKey(_minutes[i]),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: text.titleSmall)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _stops[i],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Terminal', isDense: true),
                      items: [
                        for (final t in widget.terminals)
                          DropdownMenuItem(value: t.terminalId, child: Text('${t.name} · ${t.city}')),
                      ],
                      onChanged: (v) => setState(() => _stops[i] = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 130,
                    child: i == 0
                        ? Text('Departure', style: text.bodySmall)
                        : TextField(
                            controller: _minutes[i],
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Minutes after', isDense: true),
                          ),
                  ),
                  IconButton(
                    tooltip: 'Remove this stop',
                    onPressed: i == 0 || _stops.length <= 2 ? null : () => _removeStop(i),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ]),
              ),
            TextButton.icon(onPressed: _addStop, icon: const Icon(Icons.add, size: 18), label: const Text('Add stop')),
            if (problem != null) Text(problem, style: TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.pop<_NewRoute>(context, (
                    code: _code.text.trim(),
                    name: _name.text.trim(),
                    ltfrbCaseNo: _ltfrb.text.trim(),
                    stops: [for (var i = 0; i < _stops.length; i++) (_stops[i]!, int.parse(_minutes[i].text.trim()))],
                  )),
          child: const Text('Save route'),
        ),
      ],
    );
  }
}

/// Rename a route, record its LTFRB case, or take it out of service.
class _EditRouteDialog extends StatefulWidget {
  const _EditRouteDialog({required this.route});
  final RouteSummary route;

  @override
  State<_EditRouteDialog> createState() => _EditRouteDialogState();
}

class _EditRouteDialogState extends State<_EditRouteDialog> {
  late final _name = TextEditingController(text: widget.route.routeName);
  late final _ltfrb = TextEditingController(text: widget.route.ltfrbCaseNo);
  late bool _active = widget.route.isActive;

  @override
  void dispose() {
    _name.dispose();
    _ltfrb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.route.routeCode}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _ltfrb, decoration: const InputDecoration(labelText: 'LTFRB case number (optional)')),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('In service'),
            subtitle: const Text('Out of service: passengers no longer find it and the timetable makes no '
                'trips on it. Trips already made keep their bookings; void them on Trips if they will not run.'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().length < 2
              ? null
              : () => Navigator.pop(context, (_name.text.trim(), _ltfrb.text.trim(), _active)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The fare from stop 1 to each drop-off, taking effect on a chosen day.
/// Only the fares that differ from those in force on that day are sent.
class _FaresDialog extends StatefulWidget {
  const _FaresDialog({required this.route, required this.fares});
  final RouteSummary route;
  final List<Fare> fares;

  @override
  State<_FaresDialog> createState() => _FaresDialogState();
}

class _FaresDialogState extends State<_FaresDialog> {
  final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _from = _today;
  late final List<RouteStop> _dropOffs = widget.route.stops.skip(1).toList();
  late final Map<int, TextEditingController> _amounts = {
    for (final s in _dropOffs)
      s.sequence: TextEditingController(text: _fareOn(widget.fares, s.sequence, _today)?.amount.toStringAsFixed(2)),
  };

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  static final _money = RegExp(r'^\d+(\.\d{1,2})?$');

  /// Drop-off -> amount for every fare that changes on [_from]; null when
  /// a field is not an amount.
  Map<int, String>? get _changes {
    final out = <int, String>{};
    for (final MapEntry(key: stop, value: c) in _amounts.entries) {
      final v = c.text.trim();
      if (v.isEmpty) continue;
      if (!_money.hasMatch(v)) return null;
      final amount = double.parse(v);
      if (amount != _fareOn(widget.fares, stop, _from)?.amount) out[stop] = amount.toStringAsFixed(2);
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

  @override
  Widget build(BuildContext context) {
    final changes = _changes;
    final text = Theme.of(context).textTheme;
    final first = widget.route.stops.first;
    return AlertDialog(
      title: Text('Fares · ${widget.route.routeName}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The LTFRB-approved fare from ${first.name} to each drop-off. Trips before the day it takes '
                'effect keep the fare of their own day; a ticket already sold keeps its price.',
                style: text.bodySmall),
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
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${first.name} → ${s.name}'),
                      Text(
                        switch (_fareOn(widget.fares, s.sequence, _from)) {
                          null => 'No fare on ${_date.format(_from)}',
                          final Fare f => '${peso.format(f.amount)} on ${_date.format(_from)}',
                        },
                        style: text.bodySmall,
                      ),
                    ]),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _amounts[s.sequence],
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: '₱ ', isDense: true),
                    ),
                  ),
                ]),
              ),
            if (changes == null)
              Text('A fare is an amount in pesos, like 120 or 120.50.', style: TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: changes == null || changes.isEmpty ? null : () => Navigator.pop(context, (changes, _from)),
          child: Text(changes == null || changes.isEmpty
              ? 'Save fares'
              : 'Save ${changes.length} fare${changes.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}
