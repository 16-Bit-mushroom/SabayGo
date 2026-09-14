import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../data/repositories/schedule_repository.dart';

/// Recurring departures.
///
/// A template describes a standing slot on the timetable -- route, time,
/// which days it runs, and a default crew/van. Nothing a passenger can
/// book exists until `/config/trips/generate` materialises it into an
/// actual trip for a service date; that job runs nightly in production,
/// but the office can also run it by hand from here (e.g. to backfill a
/// day, or immediately after adding a new template).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final ScheduleRepository _schedule = context.read<ScheduleRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final FleetRepository _fleet = context.read<FleetRepository>();

  List<ScheduleTemplate>? _templates;
  List<RouteSummary> _routes = [];
  List<Van> _vans = [];
  List<StaffMember> _drivers = [];
  List<StaffMember> _conductors = [];
  bool _loading = true;
  String? _error;
  bool _generating = false;

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
        _schedule.listTemplates(),
        _dispatch.listRoutes(),
        _fleet.listVans(),
        _fleet.listCrew(role: 'driver'),
        _fleet.listCrew(role: 'conductor'),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<ScheduleTemplate>;
        _routes = results[1] as List<RouteSummary>;
        _vans = results[2] as List<Van>;
        _drivers = results[3] as List<StaffMember>;
        _conductors = results[4] as List<StaffMember>;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _routeName(String routeId) =>
      _routes.firstWhere((r) => r.routeId == routeId, orElse: () => RouteSummary(
          routeId: routeId, routeCode: '?', routeName: 'Unknown route', isActive: false, stopCount: 0))
          .routeName;

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

  Future<void> _toggleTemplate(ScheduleTemplate template, bool active) async {
    try {
      await _schedule.setTemplateActive(template.templateId, active);
      _showSnack('${template.tripLabel ?? template.templateId} marked ${active ? 'active' : 'inactive'}.');
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _openAddTemplateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddTemplateDialog(
        schedule: _schedule,
        routes: _routes,
        vans: _vans,
        drivers: _drivers,
        conductors: _conductors,
      ),
    );
    if (created == true) {
      _showSnack('Schedule template created.');
      await _load();
    }
  }

  Future<void> _generateTrips() async {
    final daysAhead = await showDialog<int>(
      context: context,
      builder: (_) => const _GenerateTripsDialog(),
    );
    if (daysAhead == null) return;

    setState(() => _generating = true);
    try {
      final reports = await _schedule.generateTrips(daysAhead: daysAhead);
      if (!mounted) return;
      final created = reports.fold<int>(0, (sum, r) => sum + r.tripsCreated);
      final skipped = reports.fold<int>(0, (sum, r) => sum + r.tripsSkipped);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF222736),
          title: const Text('Trips Generated', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$created trip(s) created, $skipped skipped (already existed).',
                    style: const TextStyle(color: Colors.white70)),
                for (final r in reports)
                  if (r.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('${r.serviceDate.toIso8601String().split('T').first}:',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    for (final w in r.warnings)
                      Text('• $w', style: const TextStyle(color: Color(0xFFEBCB8B), fontSize: 12)),
                  ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      );
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Schedule Templates',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _generating ? null : _generateTrips,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8FBCBB),
                  side: const BorderSide(color: Color(0xFF8FBCBB)),
                ),
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: const Text('Generate Trips'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _openAddTemplateDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Template'),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Standing timetable slots. "Generate Trips" materialises them into actual, bookable departures.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(_error!)
                    : _buildTable(),
          ),
        ],
      ),
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

  Widget _buildTable() {
    final templates = _templates ?? [];
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: templates.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                    child: Text('No schedule templates yet.', style: TextStyle(color: Colors.white54))),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
                    dataRowMinHeight: 50,
                    dataRowMaxHeight: 60,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
                    columns: const [
                      DataColumn(label: Text('Label')),
                      DataColumn(label: Text('Route')),
                      DataColumn(label: Text('Departs')),
                      DataColumn(label: Text('Runs')),
                      DataColumn(label: Text('Active')),
                    ],
                    rows: templates.map((t) {
                      return DataRow(
                        cells: [
                          DataCell(Text(t.tripLabel ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                          DataCell(Text(_routeName(t.routeId), style: const TextStyle(color: Colors.white70))),
                          DataCell(Text(t.departureTime.substring(0, 5),
                              style: const TextStyle(color: Colors.white))),
                          DataCell(Text(t.daysSummary, style: const TextStyle(color: Colors.white70))),
                          DataCell(Switch(
                            value: t.isActive,
                            activeTrackColor: const Color(0xFF8FBCBB),
                            onChanged: (v) => _toggleTemplate(t, v),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
    );
  }
}

class _GenerateTripsDialog extends StatefulWidget {
  const _GenerateTripsDialog();

  @override
  State<_GenerateTripsDialog> createState() => _GenerateTripsDialogState();
}

class _GenerateTripsDialogState extends State<_GenerateTripsDialog> {
  int _daysAhead = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222736),
      title: const Text('Generate Trips', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Materialise trips from every active template, starting today.',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Days ahead:', style: TextStyle(color: Colors.white)),
                const Spacer(),
                IconButton(
                  onPressed: _daysAhead > 1 ? () => setState(() => _daysAhead--) : null,
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white54),
                ),
                Text('$_daysAhead', style: const TextStyle(color: Colors.white, fontSize: 16)),
                IconButton(
                  onPressed: _daysAhead < 30 ? () => setState(() => _daysAhead++) : null,
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_daysAhead),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _AddTemplateDialog extends StatefulWidget {
  const _AddTemplateDialog({
    required this.schedule,
    required this.routes,
    required this.vans,
    required this.drivers,
    required this.conductors,
  });

  final ScheduleRepository schedule;
  final List<RouteSummary> routes;
  final List<Van> vans;
  final List<StaffMember> drivers;
  final List<StaffMember> conductors;

  @override
  State<_AddTemplateDialog> createState() => _AddTemplateDialogState();
}

class _AddTemplateDialogState extends State<_AddTemplateDialog> {
  String? _routeId;
  TimeOfDay _time = const TimeOfDay(hour: 5, minute: 30);
  final _label = TextEditingController();
  String? _vanId;
  String? _driverId;
  String? _conductorId;
  // Monday-first mask.
  final List<bool> _days = List.filled(7, true);
  bool _submitting = false;
  String? _error;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_routeId == null) {
      setState(() => _error = 'Pick a route.');
      return;
    }
    if (!_days.contains(true)) {
      setState(() => _error = 'Pick at least one day.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final hh = _time.hour.toString().padLeft(2, '0');
      final mm = _time.minute.toString().padLeft(2, '0');
      await widget.schedule.createTemplate(
        routeId: _routeId!,
        departureTime: '$hh:$mm:00',
        daysOfWeek: _days.map((d) => d ? '1' : '0').join(),
        defaultVanId: _vanId,
        defaultDriverId: _driverId,
        defaultConductorId: _conductorId,
        tripLabel: _label.text,
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
      title: const Text('New Schedule Template', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Color(0xFFBF616A))),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                decoration: _decoration('Route'),
                dropdownColor: const Color(0xFF2C3244),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                value: _routeId,
                items: widget.routes
                    .map((r) => DropdownMenuItem(value: r.routeId, child: Text(r.routeName)))
                    .toList(),
                onChanged: (v) => setState(() => _routeId = v),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                },
                child: InputDecorator(
                  decoration: _decoration('Departure Time'),
                  child: Text(_time.format(context), style: const TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Runs on', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  return FilterChip(
                    label: Text(_dayLabels[i]),
                    selected: _days[i],
                    onSelected: (v) => setState(() => _days[i] = v),
                    selectedColor: const Color(0xFF8FBCBB),
                    backgroundColor: const Color(0xFF151923),
                    labelStyle: TextStyle(color: _days[i] ? const Color(0xFF151923) : Colors.white70),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Trip Label (optional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: _decoration('Default Van (optional)'),
                dropdownColor: const Color(0xFF2C3244),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                value: _vanId,
                items: widget.vans
                    .map((v) => DropdownMenuItem(value: v.vanId, child: Text(v.plateNumber)))
                    .toList(),
                onChanged: (v) => setState(() => _vanId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: _decoration('Default Driver (optional)'),
                dropdownColor: const Color(0xFF2C3244),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                value: _driverId,
                items: widget.drivers
                    .map((d) => DropdownMenuItem(value: d.userId, child: Text(d.fullName)))
                    .toList(),
                onChanged: (v) => setState(() => _driverId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: _decoration('Default Conductor (optional)'),
                dropdownColor: const Color(0xFF2C3244),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                value: _conductorId,
                items: widget.conductors
                    .map((c) => DropdownMenuItem(value: c.userId, child: Text(c.fullName)))
                    .toList(),
                onChanged: (v) => setState(() => _conductorId = v),
              ),
            ],
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
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
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
