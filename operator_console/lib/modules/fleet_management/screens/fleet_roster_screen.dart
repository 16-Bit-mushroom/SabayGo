import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';

class FleetRosterScreen extends StatefulWidget {
  const FleetRosterScreen({super.key});

  @override
  State<FleetRosterScreen> createState() => _FleetRosterScreenState();
}

class _FleetRosterScreenState extends State<FleetRosterScreen> {
  late final FleetRepository _fleet = context.read<FleetRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();

  List<Van>? _vans;
  List<StaffMember>? _crew;
  List<RouteSummary> _routes = [];
  String? _error;
  bool _loading = true;
  final _vansScroll = ScrollController();
  final _crewScroll = ScrollController();

  @override
  void dispose() {
    _vansScroll.dispose();
    _crewScroll.dispose();
    super.dispose();
  }

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
      final results = await Future.wait([
        _fleet.listVans(),
        _fleet.listCrew(),
        _dispatch.listRoutes(),
      ]);
      if (!mounted) return;
      setState(() {
        _vans = results[0] as List<Van>;
        _crew = results[1] as List<StaffMember>;
        _routes = results[2] as List<RouteSummary>;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setVanStatus(Van van, String status) async {
    try {
      await _fleet.setVanStatus(van.vanId, status);
      _showSnack('${van.plateNumber} is now marked "${_vanStatus(status)}".');
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _setCrewStatus(StaffMember staff, String status) async {
    try {
      await _fleet.setCrewStatus(staff.userId, status);
      _showSnack('${staff.fullName} is now marked "${_crewStatus(status)}".');
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _openAddVanDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddVanDialog(fleet: _fleet, routes: _routes),
    );
    if (created == true) {
      _showSnack('Van added to the fleet.');
      await _load();
    }
  }

  void _showVanDetail(Van van) {
    String? routeName;
    for (final r in _routes) {
      if (r.routeId == van.registeredRouteId) {
        routeName = r.routeName;
        break;
      }
    }
    showDialog<void>(context: context, builder: (_) => _VanDetailDialog(van: van, routeName: routeName));
  }

  void _showCrewDetail(StaffMember staff) {
    showDialog<void>(context: context, builder: (_) => _CrewDetailDialog(staff: staff));
  }

  Future<void> _openAddCrewDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddCrewDialog(fleet: _fleet),
    );
    if (created == true) {
      _showSnack('Crew member added. They can sign in with the temporary password.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Vans & Crew',
                description: 'The cooperative\'s vans, and the drivers and conductors who work '
                    'them. Click a row for details; use the ⋮ button to change a status.',
                actions: [RefreshButton(onPressed: _load, busy: _loading)],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? LoadError(message: _error!, onRetry: _load)
                        : isDesktop
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildVansTable()),
                                  const SizedBox(width: 24),
                                  Expanded(child: _buildDriversTable()),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildVansTable(),
                                    const SizedBox(height: 24),
                                    _buildDriversTable(),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVansTable() {
    final vans = _vans ?? [];
    return _RosterCard(
      title: 'Vans',
      count: vans.length,
      icon: Icons.airport_shuttle_outlined,
      addLabel: 'Add van',
      onAdd: _openAddVanDialog,
      emptyMessage: 'No vans yet. Add the first one with "Add van".',
      scroll: _vansScroll,
      columns: const [
        ('Plate number', 16, false),
        ('Make and model', 24, false),
        ('Seats', 8, true),
        ('Status', 16, false),
      ],
      rows: [
        for (final van in vans)
          _RosterRow(
            semanticLabel: '${van.plateNumber}, ${van.operationalStatus}. Opens van details.',
            onTap: () => _showVanDetail(van),
            cells: [
              Text(van.plateNumber,
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(
                [van.brand, van.model].where((s) => s != null && s.isNotEmpty).join(' '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary),
              ),
              Text('${van.seatCapacity}', style: _figures),
              _statusBadge(van.operationalStatus, _vanStatus(van.operationalStatus)),
            ],
            trailing: _buildVanStatusMenu(van),
          ),
      ],
    );
  }

  Widget _buildDriversTable() {
    final crew = _crew ?? [];
    return _RosterCard(
      title: 'Drivers and conductors',
      count: crew.length,
      icon: Icons.badge_outlined,
      addLabel: 'Add crew member',
      onAdd: _openAddCrewDialog,
      emptyMessage: 'No drivers or conductors yet. Add the first with "Add crew member".',
      scroll: _crewScroll,
      columns: const [
        ('Name', 24, false),
        ('Role', 14, false),
        ('Licence', 18, false),
        ('Status', 14, false),
      ],
      rows: [
        for (final staff in crew)
          _RosterRow(
            semanticLabel: '${staff.fullName}, ${_roleLabel(staff.role)}, ${staff.employmentStatus}. '
                'Opens crew details.',
            onTap: () => _showCrewDetail(staff),
            cells: [
              Text(staff.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(_roleLabel(staff.role),
                  overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textPrimary)),
              Text(staff.licenseNumber ?? '—', overflow: TextOverflow.ellipsis, style: _figures),
              _statusBadge(staff.employmentStatus, _crewStatus(staff.employmentStatus)),
            ],
            trailing: _buildCrewStatusMenu(staff),
          ),
      ],
    );
  }

  static TextStyle get _figures => TextStyle(
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Role in words. `coop_admin` is office staff -- never "operator", which
  /// under LTFRB usage is the franchise holder (see migration 010).
  static String _roleLabel(String role) => switch (role) {
        'driver' => 'Driver',
        'conductor' => 'Conductor',
        'coop_admin' => 'Office staff',
        'admin' => 'Administrator',
        _ => role,
      };

  /// Van and crew states in the office's words. The stored values
  /// (`maintenance`, `inactive`) are the system's.
  static String _vanStatus(String s) => switch (s) {
        'active' => 'In service',
        'maintenance' => 'Under repair',
        'inactive' => 'Not in use',
        _ => s,
      };

  static String _crewStatus(String s) => switch (s) {
        'active' => 'Working',
        'suspended' => 'Suspended',
        'inactive' => 'No longer working',
        _ => s,
      };

  Widget _buildVanStatusMenu(Van van) {
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      icon: Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
      onSelected: (status) => _setVanStatus(van, status),
      itemBuilder: (_) => [
        for (final s in const ['active', 'maintenance', 'inactive'])
          PopupMenuItem(value: s, child: Text(_vanStatus(s))),
      ],
    );
  }

  Widget _buildCrewStatusMenu(StaffMember staff) {
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      icon: Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
      onSelected: (status) => _setCrewStatus(staff, status),
      itemBuilder: (_) => [
        for (final s in const ['active', 'suspended', 'inactive'])
          PopupMenuItem(value: s, child: Text(_crewStatus(s))),
      ],
    );
  }

  /// Three states, three tones, each with its word on the chip: in service,
  /// temporarily out (maintenance, suspended), and retired.
  Widget _statusBadge(String status, String label) => StatusBadge(
        label,
        tone: switch (status) {
          'active' => Tone.success,
          'maintenance' || 'suspended' => Tone.warning,
          _ => Tone.neutral,
        },
      );
}

/// One roster row: the cells, a click target for the details, and the
/// status menu at the end (outside the click target, so opening the menu
/// never also opens the details).
class _RosterRow {
  const _RosterRow({
    required this.cells,
    required this.onTap,
    required this.trailing,
    required this.semanticLabel,
  });

  final List<Widget> cells;
  final VoidCallback onTap;
  final Widget trailing;
  final String semanticLabel;
}

/// A titled card holding one roster table.
///
/// Replaces two DataTables. Those were only as wide as their columns (the
/// heading strip stopped short of the card's edge), had no height limit
/// (the crew list ran off the bottom of the screen -- the yellow-and-black
/// overflow stripe), and gave every row a checkbox that did nothing but
/// open the details. Here the columns share the card's width, the heading
/// stays put, the rows scroll inside the card with a visible scrollbar,
/// and a click on the row opens the details.
class _RosterCard extends StatelessWidget {
  const _RosterCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.addLabel,
    required this.onAdd,
    required this.emptyMessage,
    required this.scroll,
    required this.columns,
    required this.rows,
  });

  final String title;
  final int count;
  final IconData icon;
  final String addLabel;
  final VoidCallback onAdd;
  final String emptyMessage;
  final ScrollController scroll;

  /// Label, flex share, right-aligned.
  final List<(String, int, bool)> columns;
  final List<_RosterRow> rows;

  static const double _minWidth = 520;
  static const double _menuWidth = 48;

  Widget _cell(int i, Widget child) {
    final (_, flex, numeric) = columns[i];
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  Widget _heading() => Container(
        height: 44,
        color: AppColors.surfaceSunken,
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Row(children: [
          for (var i = 0; i < columns.length; i++)
            _cell(
              i,
              Text(columns[i].$1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
            ),
          const SizedBox(width: _menuWidth),
        ]),
      );

  Widget _row(_RosterRow r) => SizedBox(
        height: 52,
        child: Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: r.semanticLabel,
              onTap: r.onTap, // restated: excludeSemantics drops the InkWell's own tap
              excludeSemantics: true,
              child: InkWell(
                onTap: r.onTap,
                hoverColor: AppColors.surfaceSunken,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Row(children: [
                    for (var i = 0; i < r.cells.length; i++) _cell(i, r.cells[i]),
                  ]),
                ),
              ),
            ),
          ),
          SizedBox(width: _menuWidth, child: Center(child: r.trailing)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
      child: Row(children: [
        Icon(icon, color: AppColors.textMuted, size: 20),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(title,
              overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (count > 0) Text('$count', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(addLabel),
        ),
      ]),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (rows.isEmpty) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(emptyMessage,
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))),
            ),
          ]);
        }

        final width = c.maxWidth < _minWidth ? _minWidth : c.maxWidth;
        // Side by side the card's height is bounded: it shrinks to its rows
        // and scrolls once they outgrow the screen. Stacked on a narrow
        // window it sits in the page's scroll view, so every row is laid
        // out -- a flexible list there has no height to fill.
        final body = c.hasBoundedHeight
            ? Flexible(
                child: Scrollbar(
                  controller: scroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: scroll,
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _row(rows[i]),
                  ),
                ),
              )
            : Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(),
                  _row(rows[i]),
                ],
              ]);

        final table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width, maxWidth: width),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_heading(), const Divider(), body],
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, if (c.hasBoundedHeight) Flexible(child: table) else table],
        );
      }),
    );
  }
}

class _AddVanDialog extends StatefulWidget {
  const _AddVanDialog({required this.fleet, required this.routes});
  final FleetRepository fleet;
  final List<RouteSummary> routes;

  @override
  State<_AddVanDialog> createState() => _AddVanDialogState();
}

class _AddVanDialogState extends State<_AddVanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _seats = TextEditingController(text: '14');
  String? _routeId;
  bool _hasCamera = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    _brand.dispose();
    _model.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.fleet.createVan(
        plateNumber: _plate.text,
        brand: _brand.text,
        model: _model.text,
        seatCapacity: int.parse(_seats.text),
        registeredRouteId: _routeId,
        hasCabinCamera: _hasCamera,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a van'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                ],
                _field(_plate, 'Plate number', validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'Required' : null),
                const SizedBox(height: 12),
                _field(_brand, 'Brand (optional)'),
                const SizedBox(height: 12),
                _field(_model, 'Model (optional)'),
                const SizedBox(height: 12),
                _field(_seats, 'Number of seats', keyboardType: TextInputType.number,
                    validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 14) return '1-14 seats';
                  return null;
                }),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: _decoration('Registered route (optional)'),
                  dropdownColor: AppColors.surfaceSunken,
                  style: TextStyle(color: AppColors.textPrimary),
                  value: _routeId,
                  items: widget.routes
                      .map((r) => DropdownMenuItem(value: r.routeId, child: Text(r.routeName)))
                      .toList(),
                  onChanged: (v) => setState(() => _routeId = v),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _hasCamera,
                  onChanged: (v) => setState(() => _hasCamera = v ?? false),
                  title: Text('Has cabin camera', style: TextStyle(color: AppColors.textPrimary)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add van'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary),
      keyboardType: keyboardType,
      decoration: _decoration(label),
      validator: validator,
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textMuted),
      );
}

class _AddCrewDialog extends StatefulWidget {
  const _AddCrewDialog({required this.fleet});
  final FleetRepository fleet;

  @override
  State<_AddCrewDialog> createState() => _AddCrewDialogState();
}

class _AddCrewDialogState extends State<_AddCrewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _license = TextEditingController();
  // Only conductor/driver are valid Role values for crew. The backend's
  // StaffIn model still accepts a stale "operator" literal left over from
  // before migration 010 renamed that role to coop_admin -- there is no
  // such Role any more, so it is never offered here.
  String _role = 'conductor';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.fleet.createCrew(
        email: _email.text,
        phoneNumber: _phone.text,
        password: _password.text,
        role: _role,
        firstName: _firstName.text,
        lastName: _lastName.text,
        licenseNumber: _role == 'driver' ? _license.text : null,
        licenseExpiryDate: _role == 'driver'
            ? DateTime.now().add(const Duration(days: 365))
            : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a crew member'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  decoration: _decoration('Role'),
                  dropdownColor: AppColors.surfaceSunken,
                  style: TextStyle(color: AppColors.textPrimary),
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'conductor', child: Text('Conductor')),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'conductor'),
                ),
                const SizedBox(height: 12),
                _field(_firstName, 'First name', required: true),
                const SizedBox(height: 12),
                _field(_lastName, 'Last name', required: true),
                const SizedBox(height: 12),
                _field(_email, 'Email (they sign in with it)', required: true),
                const SizedBox(height: 12),
                _field(_phone, 'Phone number', required: true),
                const SizedBox(height: 12),
                _field(_password, 'Temporary password', required: true, obscure: true),
                if (_role == 'driver') ...[
                  const SizedBox(height: 12),
                  _field(_license, 'Driver\'s licence number', required: true),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add crew member'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {bool required = false, bool obscure = false}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _decoration(label),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textMuted),
      );
}

/// Row-click detail views. Fields the roster table has no room for --
/// CPC papers, the camera unit's device id, a driver's full licence and
/// CTTMO record -- already exist on the backend; this just surfaces them
/// instead of adding new ones. No photos yet: `vans` has no photo column
/// at all, and wiring one up (migration + upload endpoint + storage) is
/// separate follow-on work.
class _DetailDialog extends StatelessWidget {
  const _DetailDialog({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: Text(title, style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(label, style: TextStyle(color: AppColors.textMuted)),
                    ),
                    Expanded(
                      child: Text(value,
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _VanDetailDialog extends StatelessWidget {
  const _VanDetailDialog({required this.van, this.routeName});
  final Van van;
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final brandModel = [van.brand, van.model].where((s) => s != null && s.isNotEmpty).join(' ');
    return _DetailDialog(
      title: van.plateNumber,
      rows: [
        ('Brand / Model', brandModel.isEmpty ? '—' : brandModel),
        ('Color', van.color ?? '—'),
        ('Seat capacity', van.seatCapacity.toString()),
        ('Status', _FleetRosterScreenState._vanStatus(van.operationalStatus)),
        ('Registered route', routeName ?? '—'),
        ('CPC case no.', van.cpcCaseNo ?? '—'),
        ('CPC number', van.cpcNumber ?? '—'),
        ('Cabin camera', van.hasCabinCamera ? 'Installed' : 'Not installed'),
        if (van.hasCabinCamera) ('Camera device ID', van.cameraDeviceId ?? '—'),
        if (van.hasCabinCamera)
          (
            'Camera installed',
            van.cameraInstalledAt == null
                ? '—'
                : '${van.cameraInstalledAt!.year}-${van.cameraInstalledAt!.month.toString().padLeft(2, '0')}-${van.cameraInstalledAt!.day.toString().padLeft(2, '0')}'
          ),
      ],
    );
  }
}

class _CrewDetailDialog extends StatelessWidget {
  const _CrewDetailDialog({required this.staff});
  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    return _DetailDialog(
      title: staff.fullName,
      rows: [
        ('Role', _FleetRosterScreenState._roleLabel(staff.role)),
        ('Status', _FleetRosterScreenState._crewStatus(staff.employmentStatus)),
        ('Email', staff.email),
        ('Phone', staff.phoneNumber ?? '—'),
        ('Cooperative', staff.cooperativeName ?? '—'),
        if (staff.role == 'driver') ...[
          ('License number', staff.licenseNumber ?? '—'),
          (
            'License expiry',
            staff.licenseExpiryDate == null
                ? '—'
                : '${staff.licenseExpiryDate!.year}-${staff.licenseExpiryDate!.month.toString().padLeft(2, '0')}-${staff.licenseExpiryDate!.day.toString().padLeft(2, '0')}'
          ),
          ('CTTMO ID', staff.cttmoIdNumber ?? '—'),
        ],
      ],
    );
  }
}
