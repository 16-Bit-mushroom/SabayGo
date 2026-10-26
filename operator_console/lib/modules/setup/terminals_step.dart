import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/route_repository.dart';
import 'step_frame.dart';

/// Setup, Terminals: every terminal a route stops at (brief 2.1, Table 27).
/// A route needs two. A terminal on a route in service cannot close; the
/// server says which routes.
class TerminalsStep extends StatefulWidget {
  const TerminalsStep({super.key, required this.onChanged});

  /// Tells the set-up queue to count again.
  final VoidCallback onChanged;

  @override
  State<TerminalsStep> createState() => _TerminalsStepState();
}

class _TerminalsStepState extends State<TerminalsStep> {
  late final RouteRepository _network = context.read<RouteRepository>();
  List<Terminal>? _terminals;
  String? _error;
  bool _loading = true;

  /// The terminal open in the side panel; null shows the add form.
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
      final t = await _network.terminals();
      if (mounted) setState(() => _terminals = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(Terminal? existing, TerminalDraft draft, bool another) async {
    final ok = existing == null
        ? await runAction(context, () => _network.addTerminal(draft), '${draft.name} added.')
        : await runAction(context, () => _network.editTerminal(existing.terminalId, draft), '${draft.name} saved.');
    if (!ok || !mounted) return false;
    await _load();
    widget.onChanged();
    if (!mounted) return true;
    setState(() {
      if (another) {
        _selected = null;
        _blank++;
      } else {
        _selected = existing?.terminalId ??
            _terminals?.where((t) => t.name == draft.name).firstOrNull?.terminalId;
      }
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final terminals = _terminals ?? const <Terminal>[];
    final selected = terminals.where((t) => t.terminalId == _selected).firstOrNull;
    return StepFrame(
      title: 'Terminals',
      description: 'Every terminal the route stops at, in any order. For the position, long-press the '
          'loading bay in Google Maps and copy the two numbers it shows.',
      actions: [RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading && _terminals == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : RecordList(
                  title: 'Terminals',
                  addLabel: 'Add terminal',
                  onAdd: selected == null ? null : () => setState(() => _selected = null),
                  empty: const EmptyState(
                    icon: Icons.location_on_outlined,
                    title: 'No terminals yet',
                    hint: 'Add this terminal with the form, then every other terminal on the route.',
                  ),
                  rows: [
                    for (final t in terminals)
                      RecordRow(
                        leading: Icon(Icons.location_on_outlined, color: AppColors.textMuted),
                        title: t.name,
                        subtitle: '${t.city} · '
                            '${t.geofenceM == null ? 'default zone' : 'zone ${t.geofenceM} m'} · '
                            '${t.isStaffed ? 'staffed' : 'not staffed'}',
                        badges: [
                          t.isActive ? const StatusBadge('Open', tone: Tone.success) : const StatusBadge('Closed'),
                        ],
                        selected: t.terminalId == _selected,
                        semanticLabel: '${t.name}, ${t.isActive ? 'open' : 'closed'}. Opens it to edit.',
                        onTap: () => setState(() => _selected = t.terminalId),
                      ),
                  ],
                ),
      side: selected == null
          ? SidePanel(
              title: 'Add terminal',
              child: TerminalForm(key: ValueKey('new-$_blank'), onSave: (d, another) => _save(null, d, another)),
            )
          : SidePanel(
              title: 'Edit ${selected.name}',
              onClose: () => setState(() => _selected = null),
              closeLabel: 'Back to adding',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FactLine(Icons.route,
                    selected.routes.isEmpty ? 'On no route in service' : 'On ${selected.routes.join(', ')}'),
                const SizedBox(height: AppSpacing.md),
                TerminalForm(
                  key: ValueKey(selected.terminalId),
                  terminal: selected,
                  onSave: (d, _) => _save(selected, d, false),
                  onCancel: () => setState(() => _selected = null),
                ),
              ]),
            ),
    );
  }
}

/// Add a terminal, or correct or close one.
class TerminalForm extends StatefulWidget {
  const TerminalForm({super.key, this.terminal, required this.onSave, this.onCancel});
  final Terminal? terminal;

  /// True when saved; the flag is "add another".
  final Future<bool> Function(TerminalDraft draft, bool another) onSave;
  final VoidCallback? onCancel;

  @override
  State<TerminalForm> createState() => _TerminalFormState();
}

class _TerminalFormState extends State<TerminalForm> {
  Terminal? get _t => widget.terminal;
  late final _name = TextEditingController(text: _t?.name);
  late final _city = TextEditingController(text: _t?.city ?? 'Davao City');
  late final _address = TextEditingController(text: _t?.address);
  late final _lat = TextEditingController(text: _t?.latitude.toString());
  late final _lng = TextEditingController(text: _t?.longitude.toString());
  late final _zone = TextEditingController(text: _t?.geofenceM?.toString());
  late bool _staffed = _t?.isStaffed ?? true;
  late bool _open = _t?.isActive ?? true;
  bool _busy = false;

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

  Future<void> _save(bool another) async {
    setState(() => _busy = true);
    await widget.onSave(
      TerminalDraft(
        name: _name.text.trim(),
        city: _city.text.trim(),
        address: _address.text.trim(),
        latitude: double.parse(_lat.text.trim()),
        longitude: double.parse(_lng.text.trim()),
        geofenceM: int.tryParse(_zone.text.trim()),
        isStaffed: _staffed,
        isActive: _open,
      ),
      another,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    Widget field(TextEditingController c, String label, {String? hint, bool number = false}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field(_name, 'Name', hint: 'Ecoland Terminal'),
      field(_city, 'City', hint: 'Davao City'),
      field(_address, 'Address (optional)'),
      Row(children: [
        Expanded(child: field(_lat, 'Latitude', hint: '7.0503', number: true)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: field(_lng, 'Longitude', hint: '125.5947', number: true)),
      ]),
      field(_zone, 'Terminal zone in metres (optional)', hint: 'Empty: the default in Setup, Rules & Settings', number: true),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Staffed'),
        subtitle: const Text('A2Z has a Dispatcher or office here.'),
        value: _staffed,
        onChanged: (v) => setState(() => _staffed = v),
      ),
      if (_t != null)
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
      if (problem != null) FormProblem(problem),
      FormButtons(
        adding: _t == null,
        busy: _busy,
        onSave: problem == null ? _save : null,
        onCancel: widget.onCancel,
      ),
    ]);
  }
}
