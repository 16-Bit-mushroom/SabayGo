import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';

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
        backgroundColor: isError ? const Color(0xFFBF616A) : const Color(0xFF8FBCBB),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setVanStatus(Van van, String status) async {
    try {
      await _fleet.setVanStatus(van.vanId, status);
      _showSnack('${van.plateNumber} marked $status.');
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _setCrewStatus(StaffMember staff, String status) async {
    try {
      await _fleet.setCrewStatus(staff.userId, status);
      _showSnack('${staff.fullName} marked $status.');
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
      _showSnack('Crew member provisioned.');
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
              Row(
                children: [
                  const Text(
                    'Fleet & Crew Roster',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildError(_error!)
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

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildVansTable() {
    final vans = _vans ?? [];
    return _buildCardWrapper(
      title: 'Active Fleet (Vans)',
      icon: Icons.directions_car_filled_outlined,
      onAdd: _openAddVanDialog,
      child: vans.isEmpty
          ? _buildEmpty('No vans registered yet.')
          : DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Plate No.')),
                DataColumn(label: Text('Model')),
                DataColumn(label: Text('Seats')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('')),
              ],
              rows: vans.map((van) {
                final isActive = van.operationalStatus == 'active';
                return DataRow(
                  onSelectChanged: (_) => _showVanDetail(van),
                  cells: [
                    DataCell(Text(van.plateNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    DataCell(Text(
                        [van.brand, van.model].where((s) => s != null && s.isNotEmpty).join(' '),
                        style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(van.seatCapacity.toString(),
                        style: const TextStyle(color: Colors.white70))),
                    DataCell(_buildStatusChip(van.operationalStatus, isActive)),
                    DataCell(_buildVanStatusMenu(van)),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildDriversTable() {
    final crew = _crew ?? [];
    return _buildCardWrapper(
      title: 'Registered Crew',
      icon: Icons.badge_outlined,
      onAdd: _openAddCrewDialog,
      child: crew.isEmpty
          ? _buildEmpty('No crew provisioned yet.')
          : DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('License')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('')),
              ],
              rows: crew.map((staff) {
                final isActive = staff.employmentStatus == 'active';
                return DataRow(
                  onSelectChanged: (_) => _showCrewDetail(staff),
                  cells: [
                    DataCell(Text(staff.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    DataCell(Text(staff.role, style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(staff.licenseNumber ?? '—',
                        style: const TextStyle(color: Colors.white70))),
                    DataCell(_buildStatusChip(staff.employmentStatus, isActive)),
                    DataCell(_buildCrewStatusMenu(staff)),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildVanStatusMenu(Van van) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      color: const Color(0xFF2C3244),
      onSelected: (status) => _setVanStatus(van, status),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'active', child: Text('Active', style: TextStyle(color: Colors.white))),
        PopupMenuItem(
            value: 'maintenance', child: Text('Maintenance', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'inactive', child: Text('Inactive', style: TextStyle(color: Colors.white))),
      ],
    );
  }

  Widget _buildCrewStatusMenu(StaffMember staff) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      color: const Color(0xFF2C3244),
      onSelected: (status) => _setCrewStatus(staff, status),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'active', child: Text('Active', style: TextStyle(color: Colors.white))),
        PopupMenuItem(
            value: 'suspended', child: Text('Suspended', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'inactive', child: Text('Inactive', style: TextStyle(color: Colors.white))),
      ],
    );
  }

  Widget _buildEmpty(String message) => Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(child: Text(message, style: const TextStyle(color: Colors.white54))),
      );

  Widget _buildCardWrapper({
    required String title,
    required IconData icon,
    required Widget child,
    required VoidCallback onAdd,
  }) {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary, size: 18),
                  label: Text('Add', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String text, bool isPositive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPositive ? const Color(0xFFA3BE8C).withOpacity(0.2) : const Color(0xFFEBCB8B).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPositive ? const Color(0xFFA3BE8C) : const Color(0xFFEBCB8B),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isPositive ? const Color(0xFFA3BE8C) : const Color(0xFFEBCB8B),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
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
      backgroundColor: const Color(0xFF222736),
      title: const Text('Add Van', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Color(0xFFBF616A))),
                  const SizedBox(height: 12),
                ],
                _field(_plate, 'Plate Number', validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'Required' : null),
                const SizedBox(height: 12),
                _field(_brand, 'Brand (optional)'),
                const SizedBox(height: 12),
                _field(_model, 'Model (optional)'),
                const SizedBox(height: 12),
                _field(_seats, 'Seat Capacity', keyboardType: TextInputType.number,
                    validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 14) return '1-14 seats';
                  return null;
                }),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: _decoration('Registered Route (optional)'),
                  dropdownColor: const Color(0xFF2C3244),
                  style: const TextStyle(color: Colors.white),
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
                  title: const Text('Has cabin camera', style: TextStyle(color: Colors.white70)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFF8FBCBB),
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
              : const Text('Add Van'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      decoration: _decoration(label),
      validator: validator,
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF151923),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
      backgroundColor: const Color(0xFF222736),
      title: const Text('Provision Crew', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Color(0xFFBF616A))),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  decoration: _decoration('Role'),
                  dropdownColor: const Color(0xFF2C3244),
                  style: const TextStyle(color: Colors.white),
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'conductor', child: Text('Conductor')),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'conductor'),
                ),
                const SizedBox(height: 12),
                _field(_firstName, 'First Name', required: true),
                const SizedBox(height: 12),
                _field(_lastName, 'Last Name', required: true),
                const SizedBox(height: 12),
                _field(_email, 'Email (must end .dev in dev seed data)', required: true),
                const SizedBox(height: 12),
                _field(_phone, 'Phone Number', required: true),
                const SizedBox(height: 12),
                _field(_password, 'Temporary Password', required: true, obscure: true),
                if (_role == 'driver') ...[
                  const SizedBox(height: 12),
                  _field(_license, 'License Number', required: true),
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
              : const Text('Add Crew'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {bool required = false, bool obscure = false}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF151923),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
      backgroundColor: const Color(0xFF222736),
      title: Text(title, style: const TextStyle(color: Colors.white)),
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
                      child: Text(label, style: const TextStyle(color: Colors.white54)),
                    ),
                    Expanded(
                      child: Text(value,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
        ('Status', van.operationalStatus),
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
        ('Role', staff.role),
        ('Status', staff.employmentStatus),
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
