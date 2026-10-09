import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';

/// Recurring departures.
///
/// A template describes a standing slot on the timetable -- route, time,
/// which days it runs, and a default crew/van. Nothing a passenger can
/// book exists until `/config/trips/generate` materialises it into an
/// actual trip for a service date; that job runs nightly in production,
/// but the office can also run it by hand from here (e.g. to backfill a
/// day, or immediately after adding a new template).
///
/// Laid out like the Trip Dispatcher: the list on the left, the form that
/// adds to it in a card on the right. The form used to be a dialog behind
/// a "New Template" button, which hid the timetable while the office was
/// deciding where a new slot fits in it.
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

  final _rowsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rowsScroll.dispose();
    super.dispose();
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
        backgroundColor: isError ? AppColors.danger : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleTemplate(ScheduleTemplate template, bool active) async {
    try {
      await _schedule.setTemplateActive(template.templateId, active);
      _showSnack('${template.tripLabel ?? 'Regular departure'} is now ${active ? 'in use' : 'paused'}.');
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _onTemplateCreated() async {
    _showSnack('Regular departure added.');
    await _load();
  }

  void _showDetails(ScheduleTemplate t) {
    T? find<T>(List<T> list, String? id, String Function(T) key) {
      if (id == null) return null;
      for (final e in list) {
        if (key(e) == id) return e;
      }
      return null;
    }

    showDialog<void>(
      context: context,
      builder: (_) => _TemplateDetailsDialog(
        template: t,
        routeName: _routeName(t.routeId),
        van: find<Van>(_vans, t.defaultVanId, (v) => v.vanId),
        driver: find<StaffMember>(_drivers, t.defaultDriverId, (s) => s.userId),
        conductor: find<StaffMember>(_conductors, t.defaultConductorId, (s) => s.userId),
      ),
    );
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
          title: const Text('Upcoming trips created'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$created new trip(s) created. $skipped already existed and were left as they were.'),
                for (final r in reports)
                  if (r.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('${r.serviceDate.toIso8601String().split('T').first}:',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final w in r.warnings)
                      Text('• $w', style: const TextStyle(color: AppColors.warning, fontSize: 12.5)),
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
          PageHeader(
            title: 'Timetable',
            description: 'Regular departures that repeat each week. Press "Create upcoming '
                'trips" to turn them into trips passengers can book.',
            actions: [
              FilledButton.icon(
                onPressed: _generating ? null : _generateTrips,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onFill))
                    : const Icon(Icons.event_available, size: 18),
                label: const Text('Create upcoming trips'),
              ),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTable()),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 380,
                            child: _NewTemplateCard(
                              schedule: _schedule,
                              routes: _routes,
                              vans: _vans,
                              drivers: _drivers,
                              conductors: _conductors,
                              onCreated: _onTemplateCreated,
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  /// Label, flex share. Same flex-table approach as Revenue: the table
  /// fills its card (a DataTable is only as wide as its content and left a
  /// blank band), and the heading row stays put while the rows scroll.
  static const _columns = <(String, int)>[
    ('Name', 16),
    ('Route', 20),
    ('Leaves at', 9),
    ('Days', 12),
    ('Van & crew', 11),
    ('In use', 9),
  ];

  static const double _minTableWidth = 640;

  Widget _cell(int column, Widget child) => Expanded(
        flex: _columns[column].$2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      );

  Widget _buildTable() {
    final templates = _templates ?? [];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: templates.isEmpty
          ? const EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'No regular departures yet',
              hint: 'Add the first one with the form on the right.',
            )
          : LayoutBuilder(builder: (context, c) {
              final width = c.maxWidth < _minTableWidth ? _minTableWidth : c.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: c.maxHeight,
                  child: Column(
                    children: [
                      Container(
                        height: 44,
                        color: AppColors.surfaceSunken,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Row(children: [
                          for (var i = 0; i < _columns.length; i++)
                            _cell(
                              i,
                              Text(_columns[i].$1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                            ),
                        ]),
                      ),
                      const Divider(),
                      Expanded(
                        child: Scrollbar(
                          controller: _rowsScroll,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _rowsScroll,
                            itemCount: templates.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (_, i) => _templateRow(templates[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
    );
  }

  Widget _templateRow(ScheduleTemplate t) {
    // An inactive slot is still listed -- it can be switched back on -- but
    // reads as dormant, so the live timetable is what the eye picks out.
    final ink = t.isActive ? AppColors.textPrimary : AppColors.textMuted;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(children: [
          _cell(0, Text(t.tripLabel ?? '—',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: ink))),
          _cell(1, Text(_routeName(t.routeId), overflow: TextOverflow.ellipsis, style: TextStyle(color: ink))),
          _cell(2, Text(t.departureTime.substring(0, 5),
              style: TextStyle(color: ink, fontFeatures: const [FontFeature.tabularFigures()]))),
          _cell(3, Text(t.daysSummary, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink))),
          _cell(
            4,
            OutlinedButton.icon(
              onPressed: () => _showDetails(t),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              icon: const Icon(Icons.badge_outlined, size: 16),
              label: const Text('Details'),
            ),
          ),
          _cell(
            5,
            Tooltip(
              message: t.isActive
                  ? 'In use: included when upcoming trips are created'
                  : 'Paused: skipped when upcoming trips are created',
              child: Switch(
                value: t.isActive,
                onChanged: (v) => _toggleTemplate(t, v),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Who and what a slot runs with.
///
/// Read-only, and resolved from the roster the screen already loaded, so
/// opening it costs no request. An unassigned role is said plainly along
/// with its consequence, rather than shown as a blank: a generated trip
/// with no van cannot board anyone until dispatch assigns one.
class _TemplateDetailsDialog extends StatelessWidget {
  const _TemplateDetailsDialog({
    required this.template,
    required this.routeName,
    this.van,
    this.driver,
    this.conductor,
  });

  final ScheduleTemplate template;
  final String routeName;
  final Van? van;
  final StaffMember? driver;
  final StaffMember? conductor;

  @override
  Widget build(BuildContext context) {
    final t = template;
    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: Text(t.tripLabel ?? 'Regular departure'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$routeName · departs ${t.departureTime.substring(0, 5)} · ${t.daysSummary}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Valid from ${date(t.validFrom)}'
                '${t.validUntil != null ? ' until ${date(t.validUntil!)}' : ', no end date'}'
                ' · ${t.isActive ? 'In use' : 'Paused'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              _AssignmentBlock(
                icon: Icons.airport_shuttle_outlined,
                role: 'Van',
                assigned: t.defaultVanId != null,
                title: van?.plateNumber,
                lines: [
                  if (van != null) ...[
                    [van!.brand, van!.model].whereType<String>().join(' ').trim().isEmpty
                        ? 'Make not recorded'
                        : [van!.brand, van!.model].whereType<String>().join(' '),
                    '${van!.seatCapacity} seats',
                  ],
                ],
                status: van?.operationalStatus,
                unassignedNote: 'No usual van. Trips created from this start without one.',
              ),
              const SizedBox(height: AppSpacing.md),
              _AssignmentBlock(
                icon: Icons.person_outline,
                role: 'Driver',
                assigned: t.defaultDriverId != null,
                title: driver?.fullName,
                lines: [
                  if (driver?.phoneNumber != null) driver!.phoneNumber!,
                  if (driver?.licenseNumber != null)
                    'Licence ${driver!.licenseNumber}'
                        '${driver!.licenseExpiryDate != null ? ' · expires ${date(driver!.licenseExpiryDate!)}' : ''}',
                ],
                status: driver?.employmentStatus,
                unassignedNote: 'No usual driver. Trips created from this start without one.',
              ),
              const SizedBox(height: AppSpacing.md),
              _AssignmentBlock(
                icon: Icons.confirmation_number_outlined,
                role: 'Conductor',
                assigned: t.defaultConductorId != null,
                title: conductor?.fullName,
                lines: [
                  if (conductor?.phoneNumber != null) conductor!.phoneNumber!,
                ],
                status: conductor?.employmentStatus,
                unassignedNote: 'No usual conductor. Trips created from this start without one.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// One role in the details dialog: assigned, unassigned, or assigned to
/// someone no longer in the roster.
class _AssignmentBlock extends StatelessWidget {
  const _AssignmentBlock({
    required this.icon,
    required this.role,
    required this.assigned,
    required this.title,
    required this.lines,
    required this.status,
    required this.unassignedNote,
  });

  final IconData icon;
  final String role;
  final bool assigned;
  final String? title;
  final List<String> lines;
  final String? status;
  final String unassignedNote;

  @override
  Widget build(BuildContext context) {
    // Three states, never a blank: assigned, not assigned, or assigned to
    // an id the roster no longer returns.
    final missing = assigned && title == null;
    final inactive = status != null && status != 'active';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: assigned ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: assigned ? AppColors.textPrimary : AppColors.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                if (!assigned) ...[
                  const Text('Not assigned',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(unassignedNote, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ] else if (missing)
                  const Text('Assigned record not found in the roster.',
                      style: TextStyle(fontSize: 14, color: AppColors.warning))
                else ...[
                  Row(children: [
                    Flexible(
                      child: Text(title!,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    if (inactive) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warningContainer,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(status!.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning)),
                      ),
                    ],
                  ]),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(l, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ),
                ],
              ],
            ),
          ),
        ],
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
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('Create upcoming trips'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Creates bookable trips from every regular departure that is in use, '
                'starting today. Trips that already exist are left alone.',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('How many days ahead:', style: TextStyle(color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                  onPressed: _daysAhead > 1 ? () => setState(() => _daysAhead--) : null,
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
                ),
                Text('$_daysAhead', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                IconButton(
                  onPressed: _daysAhead < 30 ? () => setState(() => _daysAhead++) : null,
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.textMuted),
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
          child: const Text('Create trips'),
        ),
      ],
    );
  }
}

/// The "new template" form, as a card beside the table rather than a
/// dialog -- the same arrangement as "Dispatch Special Trip", so the two
/// screens that create departures are laid out alike. After a successful
/// create it clears itself for the next slot instead of closing.
class _NewTemplateCard extends StatefulWidget {
  const _NewTemplateCard({
    required this.schedule,
    required this.routes,
    required this.vans,
    required this.drivers,
    required this.conductors,
    required this.onCreated,
  });

  final ScheduleRepository schedule;
  final List<RouteSummary> routes;
  final List<Van> vans;
  final List<StaffMember> drivers;
  final List<StaffMember> conductors;
  final Future<void> Function() onCreated;

  @override
  State<_NewTemplateCard> createState() => _NewTemplateCardState();
}

class _NewTemplateCardState extends State<_NewTemplateCard> {
  static const _defaultTime = TimeOfDay(hour: 5, minute: 30);

  String? _routeId;
  TimeOfDay _time = _defaultTime;
  final _label = TextEditingController();
  String? _vanId;
  String? _driverId;
  String? _conductorId;
  // Monday-first mask.
  final List<bool> _days = List.filled(7, true);
  bool _submitting = false;
  int _epoch = 0;
  String? _error;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _reset() {
    _routeId = null;
    _time = _defaultTime;
    _label.clear();
    _vanId = null;
    _driverId = null;
    _conductorId = null;
    _days.fillRange(0, 7, true);
    _epoch++;
    _error = null;
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
      if (!mounted) return;
      setState(_reset);
      await widget.onCreated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a regular departure', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('A trip that repeats on the chosen days, with its usual van and crew.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.dangerContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Route'),
              isExpanded: true,
              initialValue: _routeId,
              // Keyed by a reset counter, so clearing the form after a create
              // really clears it: initialValue is read only when built.
              key: ValueKey('route-$_epoch'),
              items: widget.routes
                  .map((r) => DropdownMenuItem(value: r.routeId, child: Text(r.routeName)))
                  .toList(),
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Leaves at',
                  suffixIcon: Icon(Icons.schedule),
                ),
                child: Text(_time.format(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Runs on', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (i) {
                return Tooltip(
                  message: _dayNames[i],
                  child: FilterChip(
                    label: Text(_dayLabels[i]),
                    selected: _days[i],
                    showCheckmark: false,
                    onSelected: (v) => setState(() => _days[i] = v),
                    labelStyle: TextStyle(
                      color: _days[i] ? AppColors.onFill : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'Name (optional)', hintText: 'For example: Morning run'),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Usual van (optional)'),
              isExpanded: true,
              initialValue: _vanId,
              key: ValueKey('van-$_epoch'),
              items: widget.vans
                  .map((v) => DropdownMenuItem(value: v.vanId, child: Text(v.plateNumber)))
                  .toList(),
              onChanged: (v) => setState(() => _vanId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Usual driver (optional)'),
              isExpanded: true,
              initialValue: _driverId,
              key: ValueKey('driver-$_epoch'),
              items: widget.drivers
                  .map((d) => DropdownMenuItem(value: d.userId, child: Text(d.fullName)))
                  .toList(),
              onChanged: (v) => setState(() => _driverId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Usual conductor (optional)'),
              isExpanded: true,
              initialValue: _conductorId,
              key: ValueKey('conductor-$_epoch'),
              items: widget.conductors
                  .map((c) => DropdownMenuItem(value: c.userId, child: Text(c.fullName)))
                  .toList(),
              onChanged: (v) => setState(() => _conductorId = v),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onFill))
                  : const Icon(Icons.add),
              label: const Text('Add regular departure'),
            ),
          ],
        ),
      ),
    );
  }
}
