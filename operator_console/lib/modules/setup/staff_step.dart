import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../viewmodels/auth_provider.dart';
import '../fleet_management/roster_parts.dart';
import '../fleet_management/roster_transfers.dart';
import 'step_frame.dart';

/// Setup, Staff: the accounts that sign in. Dispatchers ride the vans and
/// are validated before they can be assigned to a trip; Cashiers and
/// Terminal Managers work at the desk and are not (brief 3).
class StaffStep extends StatefulWidget {
  const StaffStep({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<StaffStep> createState() => _StaffStepState();
}

class _StaffStepState extends State<StaffStep> {
  late final FleetRepository _fleet = context.read<FleetRepository>();
  late final bool _canEdit = context.read<AuthProvider>().profile?.role.isManager ?? false;
  List<StaffMember>? _crew;
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
      final crew = await _fleet.listCrew();
      if (mounted) setState(() => _crew = crew);
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

  Future<void> _setStatus(StaffMember s, String status) async {
    if (await runAction(context, () => _fleet.setCrewStatus(s.userId, status),
        '${s.fullName} is now marked "${Roster.crewStatus(status)}".')) {
      await _changed(select: s.userId);
    }
  }

  Future<void> _validate(StaffMember s, String status) async {
    if (await runAction(context, () => _fleet.validate('crew', s.userId, status),
        '${s.fullName}: ${Roster.validationWord(status)}.')) {
      await _changed(select: s.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = _crew ?? const <StaffMember>[];
    final selected = crew.where((s) => s.userId == _selected).firstOrNull;
    return StepFrame(
      title: 'Staff',
      description: 'Everyone who signs in: Dispatchers, who ride the vans, and the office. '
          'At least one validated Dispatcher and one Cashier are needed before the first trip.',
      actions: [RosterTransfers(onImported: () => _changed()), RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading && _crew == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : RecordList(
                  title: 'Staff',
                  addLabel: _canEdit ? 'Add staff member' : null,
                  onAdd: _canEdit && selected != null ? () => setState(() => _selected = null) : null,
                  empty: const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No staff yet',
                    hint: 'Add a Dispatcher and a Cashier with the form.',
                  ),
                  rows: [
                    for (final s in crew)
                      RecordRow(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.surfaceSunken,
                          child: Text(s.firstName.characters.first.toUpperCase(),
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        ),
                        title: s.fullName,
                        subtitle: '${Roster.roleLabel(s.role)} · ${Roster.crewStatus(s.employmentStatus)}',
                        badges: [
                          s.role == 'dispatcher'
                              ? Roster.validationBadge(s.validationStatus)
                              : Tooltip(
                                  message: Roster.officeNoValidation,
                                  child: Text('Not needed', style: Theme.of(context).textTheme.bodySmall),
                                ),
                        ],
                        selected: s.userId == _selected,
                        semanticLabel: '${s.fullName}, ${Roster.roleLabel(s.role)}. Opens the record.',
                        onTap: () => setState(() => _selected = s.userId),
                      ),
                  ],
                ),
      side: selected != null
          ? _panel(selected)
          : !_canEdit
              ? null
              : SidePanel(
                  title: 'Add staff member',
                  child: StaffForm(
                    key: ValueKey('staff-$_blank'),
                    fleet: _fleet,
                    onSaved: (created, another) => _changed(select: created.userId, another: another),
                  ),
                ),
    );
  }

  Widget _panel(StaffMember s) {
    final text = Theme.of(context).textTheme;
    final dispatcher = s.role == 'dispatcher';
    return SidePanel(
      title: s.fullName,
      onClose: () => setState(() => _selected = null),
      closeLabel: _canEdit ? 'Back to adding' : 'Close',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FactRow('Role', Roster.roleLabel(s.role)),
        FactRow('Signs in with', s.email),
        FactRow('Phone', s.phoneNumber ?? 'Not recorded'),
        const SizedBox(height: AppSpacing.md),
        _canEdit
            ? StatusPicker(
                value: s.employmentStatus,
                options: const ['active', 'suspended', 'inactive'],
                word: Roster.crewStatus,
                onChanged: (v) => _setStatus(s, v),
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Roster.statusBadge(s.employmentStatus, Roster.crewStatus(s.employmentStatus))),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        if (dispatcher)
          ValidationPanel(
            status: s.validationStatus,
            canDecide: _canEdit,
            checks: [
              RecordCheck('Signs in as ${s.email}'),
              s.phoneNumber == null
                  ? const RecordCheck('No phone number recorded', met: false)
                  : RecordCheck('Reached on ${s.phoneNumber}'),
            ],
            onDecide: (v) => _validate(s, v),
          )
        else ...[
          Text('Validation: not needed', style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(Roster.officeNoValidation, style: text.bodySmall),
        ],
      ]),
    );
  }
}

/// A staff account. The operator (the van owner) has no login and is added
/// under Operators & vans instead.
class StaffForm extends StatefulWidget {
  const StaffForm({super.key, required this.fleet, required this.onSaved});
  final FleetRepository fleet;
  final Future<void> Function(StaffMember created, bool another) onSaved;

  @override
  State<StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<StaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'dispatcher';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _email, _phone, _password]) {
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
      final created = await widget.fleet.createCrew(
        email: _email.text,
        phoneNumber: _phone.text,
        password: _password.text,
        role: _role,
        firstName: _firstName.text,
        lastName: _lastName.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${created.fullName} added. They sign in with the temporary password.'),
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
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: const [
            DropdownMenuItem(value: 'dispatcher', child: Text('Dispatcher')),
            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
            DropdownMenuItem(value: 'terminal_manager', child: Text('Terminal Manager')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'dispatcher'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _role == 'dispatcher'
              ? 'Rides the van, marks reservations Paid and lists walk-ups. Validated before a trip.'
              : 'Works at the desk. Not validated: office accounts are never assigned to a van.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: TextFormField(controller: _firstName,
              decoration: const InputDecoration(labelText: 'First name'), validator: required)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: TextFormField(controller: _lastName,
              decoration: const InputDecoration(labelText: 'Last name'), validator: required)),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', helperText: 'They sign in with it'),
            validator: required),
        const SizedBox(height: AppSpacing.md),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number', hintText: '09XXXXXXXXX'),
            validator: required),
        const SizedBox(height: AppSpacing.md),
        PasswordField(controller: _password, label: 'Temporary password', validator: required),
        if (_error != null) FormProblem(_error!, refused: true),
        FormButtons(adding: true, busy: _busy, onSave: _save),
      ]),
    );
  }
}
