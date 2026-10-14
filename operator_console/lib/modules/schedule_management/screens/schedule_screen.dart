import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
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

  List<ScheduleTemplate>? _templates;
  List<RouteSummary> _routes = [];
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
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<ScheduleTemplate>;
        _routes = results[1] as List<RouteSummary>;
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
                      Text('• $w', style: TextStyle(color: AppColors.warning, fontSize: 12.5)),
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
                    ? SizedBox(
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
    ('Name', 20),
    ('Route', 27),
    ('Leaves at', 9),
    ('Days', 12),
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
                                  style: TextStyle(
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
            Text('Creates bookable trips from every regular departure that is in use, '
                'starting today. Trips that already exist are left alone.',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('How many days ahead:', style: TextStyle(color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                  onPressed: _daysAhead > 1 ? () => setState(() => _daysAhead--) : null,
                  icon: Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
                ),
                Text('$_daysAhead', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                IconButton(
                  onPressed: _daysAhead < 30 ? () => setState(() => _daysAhead++) : null,
                  icon: Icon(Icons.add_circle_outline, color: AppColors.textMuted),
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
    required this.onCreated,
  });

  final ScheduleRepository schedule;
  final List<RouteSummary> routes;
  final Future<void> Function() onCreated;

  @override
  State<_NewTemplateCard> createState() => _NewTemplateCardState();
}

class _NewTemplateCardState extends State<_NewTemplateCard> {
  static const _defaultTime = TimeOfDay(hour: 5, minute: 30);

  String? _routeId;
  TimeOfDay _time = _defaultTime;
  final _label = TextEditingController();
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
            Text('A trip that repeats on the chosen days. The van and the Dispatcher '
                'are assigned to each trip at the van\'s turn, on the Trips page.',
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
                child: Text(_error!, style: TextStyle(color: AppColors.danger)),
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
            Text('Runs on', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
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
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _submitting
                  ? SizedBox(
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
