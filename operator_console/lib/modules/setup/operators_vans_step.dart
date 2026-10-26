import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../viewmodels/auth_provider.dart';
import '../fleet_management/roster_parts.dart';
import '../fleet_management/roster_transfers.dart';
import '../fleet_management/van_photos.dart';
import 'step_frame.dart';

/// Setup, Operators & vans (Member Records, brief 8): the van owners, who
/// always drive and have no login, and their vans, one each. The Terminal
/// Manager adds and validates; the Cashier reads. Import and export are
/// logged.
class OperatorsVansStep extends StatefulWidget {
  const OperatorsVansStep({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<OperatorsVansStep> createState() => _OperatorsVansStepState();
}

class _OperatorsVansStepState extends State<OperatorsVansStep> {
  late final FleetRepository _fleet = context.read<FleetRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final bool _canEdit = context.read<AuthProvider>().profile?.role.isManager ?? false;

  List<Van>? _vans;
  List<OperatorRecord>? _operators;
  List<RouteSummary> _routes = const [];
  String? _error;
  bool _loading = true;

  /// 'operators' | 'vans'. Opens on operators until there is one: a van
  /// needs its operator first.
  String? _list;
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
      final r = await Future.wait([_fleet.listOperators(), _fleet.listVans(), _dispatch.listRoutes()]);
      if (!mounted) return;
      setState(() {
        _operators = r[0] as List<OperatorRecord>;
        _vans = r[1] as List<Van>;
        _routes = r[2] as List<RouteSummary>;
        _list ??= _operators!.isEmpty ? 'operators' : 'vans';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changed({String? select, bool another = false}) async {
    await _load();
    widget.onChanged();
    if (!mounted) return;
    setState(() {
      _selected = another ? null : select;
      if (another) _blank++;
    });
  }

  Future<void> _validate(String kind, String id, String name, String status) async {
    if (await runAction(context, () => _fleet.validate(kind, id, status), '$name: ${Roster.validationWord(status)}.')) {
      await _changed(select: id);
    }
  }

  Future<void> _setVanStatus(Van van, String status) async {
    if (await runAction(context, () => _fleet.setVanStatus(van.vanId, status),
        '${van.plateNumber} is now marked "${Roster.vanStatus(status)}".')) {
      await _changed(select: van.vanId);
    }
  }

  Future<void> _photos(Van van) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => VanPhotosDialog(van: van));
    if (changed == true) await _changed(select: van.vanId);
  }

  void _show(String list) => setState(() {
        _list = list;
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final list = _list ?? 'vans';
    return StepFrame(
      title: 'Operators & vans',
      description: 'The van owners, who always drive, and their vans, one each. ${Roster.validationRule}',
      actions: [RosterTransfers(onImported: () => _changed()), RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading && _vans == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : list == 'vans'
                  ? _vanList()
                  : _operatorList(),
      side: _side(list),
    );
  }

  Widget _switch(String list) => SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'operators', label: Text('Operators (${_operators?.length ?? 0})')),
          ButtonSegment(value: 'vans', label: Text('Vans (${_vans?.length ?? 0})')),
        ],
        selected: {list},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _show(s.first),
      );

  Widget _operatorList() {
    final ops = _operators ?? const <OperatorRecord>[];
    return RecordList(
      title: 'Operators',
      header: _switch('operators'),
      addLabel: _canEdit ? 'Add operator' : null,
      onAdd: _canEdit && _selected != null ? () => setState(() => _selected = null) : null,
      empty: const EmptyState(
        icon: Icons.person_outline,
        title: 'No operators yet',
        hint: 'Add each van owner with the form, or import the binder.',
      ),
      rows: [
        for (final op in ops)
          RecordRow(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceSunken,
              child: Text(op.fullName.characters.first.toUpperCase(),
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            ),
            title: op.fullName,
            subtitle: '${op.licenseNumber}${op.licenseExpired ? ' · licence expired' : ''}'
                ' · ${op.plateNumber ?? 'no van yet'}',
            badges: [Roster.validationBadge(op.validationStatus)],
            selected: op.operatorId == _selected,
            semanticLabel: '${op.fullName}, ${Roster.validationWord(op.validationStatus)}. Opens the record.',
            onTap: () => setState(() => _selected = op.operatorId),
          ),
      ],
    );
  }

  Widget _vanList() {
    final vans = _vans ?? const <Van>[];
    return RecordList(
      title: 'Vans',
      header: _switch('vans'),
      addLabel: _canEdit ? 'Add van' : null,
      onAdd: _canEdit && _selected != null ? () => setState(() => _selected = null) : null,
      empty: const EmptyState(
        icon: Icons.airport_shuttle_outlined,
        title: 'No vans yet',
        hint: 'Add the operator first, then the van with the form.',
      ),
      rows: [
        for (final van in vans)
          RecordRow(
            leading: SizedBox(width: 92, child: Align(alignment: Alignment.centerLeft, child: PlateTag(van.plateNumber))),
            title: van.operatorName ?? 'No operator',
            subtitle: '${Roster.vanStatus(van.operationalStatus)} · ${van.photos.length} of 4 photos',
            badges: [Roster.validationBadge(van.validationStatus)],
            selected: van.vanId == _selected,
            semanticLabel: '${van.plateNumber}, ${Roster.validationWord(van.validationStatus)}. Opens the record.',
            onTap: () => setState(() => _selected = van.vanId),
          ),
      ],
    );
  }

  Widget? _side(String list) {
    if (list == 'operators') {
      final op = (_operators ?? const <OperatorRecord>[]).where((o) => o.operatorId == _selected).firstOrNull;
      if (op != null) return _operatorPanel(op);
      if (!_canEdit) return null;
      return SidePanel(
        title: 'Add operator',
        child: OperatorForm(
          key: ValueKey('op-$_blank'),
          fleet: _fleet,
          onSaved: (created, another) => _changed(select: created.operatorId, another: another),
        ),
      );
    }
    final van = (_vans ?? const <Van>[]).where((v) => v.vanId == _selected).firstOrNull;
    if (van != null) return _vanPanel(van);
    if (!_canEdit) return null;
    final free = [for (final o in _operators ?? const <OperatorRecord>[]) if (o.vanId == null) o];
    if (_operators != null && free.isEmpty) {
      return SidePanel(
        title: 'Add van',
        child: BlockedNotice(
          message: _operators!.isEmpty
              ? 'A van belongs to its operator. Add the operator first.'
              : 'Every operator on the roster already has a van: one van each. Add the new van\'s operator first.',
          action: 'Add operator',
          onAction: () => _show('operators'),
        ),
      );
    }
    return SidePanel(
      title: 'Add van',
      child: VanForm(
        key: ValueKey('van-$_blank'),
        fleet: _fleet,
        operators: free,
        routes: _routes,
        onSaved: (created, another) => _changed(select: created.vanId, another: another),
      ),
    );
  }

  Widget _operatorPanel(OperatorRecord op) {
    final expiry = op.licenseExpiry;
    return SidePanel(
      title: op.fullName,
      onClose: () => setState(() => _selected = null),
      closeLabel: _canEdit ? 'Back to adding' : 'Close',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FactRow('Licence', op.licenseNumber),
        FactRow('Licence expires', expiry == null ? 'Not recorded' : '${Roster.day(expiry)}${op.licenseExpired ? ' (expired)' : ''}',
            colour: op.licenseExpired ? AppColors.danger : null),
        FactRow('Contact', op.contactNumber.isEmpty ? 'Not recorded' : op.contactNumber),
        FactRow('Van', op.plateNumber ?? 'None yet'),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        ValidationPanel(
          status: op.validationStatus,
          canDecide: _canEdit,
          checks: [
            RecordCheck('Licence ${op.licenseNumber} on record'),
            if (expiry == null)
              const RecordCheck('No licence expiry recorded', met: false)
            else if (op.licenseExpired)
              RecordCheck('Licence expired on ${Roster.day(expiry)}: a Start warns about it', met: false),
            if (op.importBatchId != null)
              const RecordCheck('Imported from the binder: whoever imported it cannot validate it', met: false),
          ],
          onDecide: (s) => _validate('operators', op.operatorId, op.fullName, s),
        ),
      ]),
    );
  }

  Widget _vanPanel(Van van) {
    const words = {'front': 'front', 'rear': 'rear', 'left': 'left side', 'right': 'right side'};
    final missing = [for (final s in Van.photoSides) if (!van.photos.containsKey(s)) words[s]!];
    final route = _routes.where((r) => r.routeId == van.registeredRouteId).firstOrNull;
    final brandModel = [van.brand, van.model].where((s) => s != null && s.isNotEmpty).join(' ');
    return SidePanel(
      title: van.plateNumber,
      onClose: () => setState(() => _selected = null),
      closeLabel: _canEdit ? 'Back to adding' : 'Close',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FactRow('Operator', van.operatorName ?? 'None'),
        FactRow('Registered route', route?.routeName ?? 'Not recorded'),
        FactRow('Brand / model', brandModel.isEmpty ? 'Not recorded' : brandModel),
        FactRow('Spaces', '${van.seatCapacity}'),
        FactRow('CPC case / number', '${van.cpcCaseNo ?? '—'} / ${van.cpcNumber ?? '—'}'),
        FactRow('Cabin camera', van.hasCabinCamera ? 'Installed' : 'Not installed'),
        const SizedBox(height: AppSpacing.md),
        _canEdit
            ? StatusPicker(
                value: van.operationalStatus,
                options: const ['active', 'maintenance', 'inactive'],
                word: Roster.vanStatus,
                onChanged: (v) => _setVanStatus(van, v),
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Roster.statusBadge(van.operationalStatus, Roster.vanStatus(van.operationalStatus))),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _photos(van),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text('Photographs (${van.photos.length} of 4)'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        ValidationPanel(
          status: van.validationStatus,
          canDecide: _canEdit,
          checks: [
            missing.isEmpty
                ? const RecordCheck('All four photographs are in')
                : RecordCheck('Photographs missing: ${missing.join(', ')}', met: false, blocks: true),
            if (van.operatorName == null) const RecordCheck('No operator on the record', met: false),
            if (van.importBatchId != null)
              const RecordCheck('Imported from the binder: whoever imported it cannot validate it', met: false),
          ],
          onDecide: (s) => _validate('vans', van.vanId, van.plateNumber, s),
        ),
      ]),
    );
  }
}

/// A van owner, added to the roster as Pending.
class OperatorForm extends StatefulWidget {
  const OperatorForm({super.key, required this.fleet, required this.onSaved});
  final FleetRepository fleet;
  final Future<void> Function(OperatorRecord created, bool another) onSaved;

  @override
  State<OperatorForm> createState() => _OperatorFormState();
}

class _OperatorFormState extends State<OperatorForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _licence = TextEditingController();
  DateTime? _expiry;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _licence.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 15),
      helpText: 'Licence expires on',
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save(bool another) async {
    if (!_formKey.currentState!.validate()) return;
    if (_expiry == null) {
      setState(() => _error = 'Pick the licence expiry date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.fleet.createOperator(
        fullName: _name.text,
        contactNumber: _contact.text,
        licenseNumber: _licence.text,
        licenseExpiry: _expiry!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${created.fullName} added, Pending until validated.'), behavior: SnackBarBehavior.floating));
      await widget.onSaved(created, another);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
    final expiry = _expiry;
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name, as on the licence'),
            validator: required),
        const SizedBox(height: AppSpacing.md),
        TextFormField(controller: _contact, decoration: const InputDecoration(labelText: 'Mobile number',
            hintText: '09XXXXXXXXX'), validator: required),
        const SizedBox(height: AppSpacing.md),
        TextFormField(controller: _licence, decoration: const InputDecoration(labelText: 'LTO licence number',
            hintText: 'N01-23-456789'), validator: required),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(
            child: Text(expiry == null ? 'Licence expiry: not set' : 'Licence expiry: ${Roster.day(expiry)}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          OutlinedButton.icon(
            onPressed: _pickExpiry,
            icon: const Icon(Icons.event, size: 18),
            label: Text(expiry == null ? 'Pick date' : 'Change'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Text('Saved as Pending until the Terminal Manager validates it.', style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) FormProblem(_error!, refused: true),
        FormButtons(adding: true, busy: _busy, onSave: _save),
      ]),
    );
  }
}

/// A van, under an operator who has none yet: one van each.
class VanForm extends StatefulWidget {
  const VanForm({
    super.key,
    required this.fleet,
    required this.operators,
    required this.routes,
    required this.onSaved,
  });
  final FleetRepository fleet;
  final List<OperatorRecord> operators;
  final List<RouteSummary> routes;
  final Future<void> Function(Van created, bool another) onSaved;

  @override
  State<VanForm> createState() => _VanFormState();
}

class _VanFormState extends State<VanForm> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _seats = TextEditingController(text: '14');
  String? _routeId;
  String? _operatorId;
  bool _hasCamera = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_plate, _brand, _model, _seats]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool another) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.fleet.createVan(
        plateNumber: _plate.text,
        operatorId: _operatorId!,
        brand: _brand.text,
        model: _model.text,
        seatCapacity: int.parse(_seats.text),
        registeredRouteId: _routeId,
        hasCabinCamera: _hasCamera,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_plate.text.trim().toUpperCase()} added. Upload its four photographs to validate it.'),
          behavior: SnackBarBehavior.floating));
      await widget.onSaved(created, another);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _operatorId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Operator (the owner, who drives)'),
          items: [
            for (final o in widget.operators)
              DropdownMenuItem(value: o.operatorId, child: Text('${o.fullName} · ${o.licenseNumber}')),
          ],
          onChanged: (v) => setState(() => _operatorId = v),
          validator: (v) => v == null ? 'Pick the operator' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Plate number'),
          validator: (v) => (v == null || v.trim().length < 3) ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)'))),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Model (optional)'))),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _seats,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Passenger spaces', helperText: 'A2Z\'s rule is 14'),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return n == null || n < 1 || n > 14 ? '1 to 14' : null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _routeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Registered route (optional)'),
          items: [for (final r in widget.routes) DropdownMenuItem(value: r.routeId, child: Text(r.routeName))],
          onChanged: (v) => setState(() => _routeId = v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _hasCamera,
          onChanged: (v) => setState(() => _hasCamera = v ?? false),
          title: const Text('Has a cabin camera'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Text('Saved as Pending. It can be validated once its four photographs are in.',
            style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) FormProblem(_error!, refused: true),
        FormButtons(adding: true, busy: _busy, onSave: _save),
      ]),
    );
  }
}
