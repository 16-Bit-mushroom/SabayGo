import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../setup/step_frame.dart';

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
  const ScheduleScreen({super.key, this.onChanged, required this.onOpenRoute});

  /// Setup's queue counts again when a departure is added or paused.
  final VoidCallback? onChanged;

  /// A departure needs a route in service: the way there when none is.
  final VoidCallback onOpenRoute;

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
      _showSnack('${template.tripLabel ?? 'Trip schedule'} is now ${active ? 'in use' : 'off'}.');
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _onTemplateCreated() async {
    _showSnack('Trip schedule added.');
    await _load();
    widget.onChanged?.call();
  }

  /// Edit: the add form, filled in, in a window over the list.
  Future<void> _editTemplate(ScheduleTemplate t) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit trip schedule'),
        content: SizedBox(
          width: 440,
          child: _NewTemplateCard(
            schedule: _schedule,
            routes: [for (final r in _routes) if (r.isActive || r.routeId == t.routeId) r],
            editing: t,
            onCreated: () async => Navigator.pop(ctx, true),
            onNewRoute: () {},
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
    if (saved != true) return;
    _showSnack('${t.tripLabel ?? 'Trip schedule'} saved. Trips already posted keep their time.');
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _deleteTemplate(ScheduleTemplate t) async {
    final name = t.tripLabel ?? 'The ${_clock(t.departureTime)} schedule';
    final ok = await askConfirm(
      context,
      title: 'Delete $name?',
      body: 'No new trips will be posted from it. Trips already posted from it '
          'stay on the Trips page with their bookings. To stop it for a while '
          'instead, switch it off under "In use".',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await _schedule.deleteTemplate(t.templateId);
      _showSnack('$name deleted.');
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepFrame(
      title: 'Trip Schedules',
      description: 'Trips that repeat every week at the same time. "Post 7 days of trips" on the Trips '
          'page makes them bookable; a schedule switched off is left out.',
      actions: [RefreshButton(onPressed: _load, busy: _loading)],
      list: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : _buildTable(),
      addLabel: 'Add trip schedule',
      openWhenEmpty: _templates != null && _templates!.isEmpty,
      // Like Route and Fares: a step that waits says why and how to get
      // there, not an empty form.
      addForm: SidePanel(
        title: 'Add a trip schedule',
        info: 'A trip that repeats on the chosen days. The van and the Dispatcher are assigned to each '
            'trip at the van\'s turn, on the Trips page.',
        child: _routes.any((r) => r.isActive)
            ? _NewTemplateCard(
                schedule: _schedule,
                routes: _routes,
                onCreated: _onTemplateCreated,
                onNewRoute: widget.onOpenRoute,
              )
            : BlockedNotice(
                message: 'A trip schedule runs on a route in service, and there is none yet.',
                action: 'Go to Route',
                onAction: widget.onOpenRoute,
              ),
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
    ('In use', 8),
    ('', 14),
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
          ? EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'No trip schedules yet',
              hint: _routes.any((r) => r.isActive)
                  ? 'Add the first one with the form on the right.'
                  : 'A trip schedule needs a route in service first.',
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

  /// "05:30:00" as "5:30 AM", as the Trips page shows times.
  static String _clock(String hms) {
    final p = hms.split(':');
    final h = int.parse(p[0]), m = p[1];
    return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'AM' : 'PM'}';
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
          _cell(2, Text(_clock(t.departureTime),
              style: TextStyle(color: ink, fontFeatures: const [FontFeature.tabularFigures()]))),
          _cell(3, Text(t.daysSummary, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink))),
          _cell(
            4,
            Tooltip(
              message: t.isActive
                  ? 'In use: posted with the 7 days of trips'
                  : 'Off: skipped when the 7 days of trips are posted',
              child: Switch(
                value: t.isActive,
                onChanged: (v) => _toggleTemplate(t, v),
              ),
            ),
          ),
          _cell(
            5,
            Row(mainAxisSize: MainAxisSize.min, children: [
              _RowAction(icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editTemplate(t)),
              const SizedBox(width: 4),
              _RowAction(
                  icon: Icons.delete_outline, label: 'Delete', danger: true, onTap: () => _deleteTemplate(t)),
            ]),
          ),
        ]),
      ),
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
    required this.onNewRoute,
    this.editing,
  });

  /// Set when the form edits this schedule (in the Edit window) rather
  /// than adding one.
  final ScheduleTemplate? editing;

  final ScheduleRepository schedule;
  final List<RouteSummary> routes;
  final Future<void> Function() onCreated;

  /// "Add a new route", the last choice in the Route list: opens Setup ›
  /// Route, where a route is made (12 Nov).
  final VoidCallback onNewRoute;

  static const newRoute = '__new_route__';

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
  void initState() {
    super.initState();
    final t = widget.editing;
    if (t != null) {
      _routeId = t.routeId;
      final hm = t.departureTime.split(':');
      _time = TimeOfDay(hour: int.parse(hm[0]), minute: int.parse(hm[1]));
      _label.text = t.tripLabel ?? '';
      for (var i = 0; i < 7 && i < t.daysOfWeek.length; i++) {
        _days[i] = t.daysOfWeek[i] == '1';
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// With one route -- A2Z's case -- it is chosen already, and stays
  /// chosen after each departure is added.
  String? get _onlyRoute => widget.routes.length == 1 ? widget.routes.first.routeId : null;
  String? get _route => _routeId ?? _onlyRoute;

  void _reset() {
    _routeId = null;
    _time = _defaultTime;
    _label.clear();
    _days.fillRange(0, 7, true);
    _epoch++;
    _error = null;
  }

  Future<void> _submit() async {
    if (_route == null) {
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
      final t = widget.editing;
      if (t != null) {
        await widget.schedule.updateTemplate(
          t.templateId,
          routeId: _route == t.routeId ? null : _route,
          departureTime: '$hh:$mm:00',
          daysOfWeek: _days.map((d) => d ? '1' : '0').join(),
          tripLabel: _label.text.trim(),
        );
        if (!mounted) return;
        await widget.onCreated();
        return;
      }
      await widget.schedule.createTemplate(
        routeId: _route!,
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
    return SizedBox(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.editing != null) ...[
              Text('Trips already posted keep their time and bookings; '
                  'trips posted from now on follow this change.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
            ],
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
              initialValue: _route,
              // Keyed by a reset counter, so clearing the form after a create
              // really clears it: initialValue is read only when built.
              key: ValueKey('route-$_epoch'),
              items: [
                ...widget.routes.map((r) => DropdownMenuItem(value: r.routeId, child: Text(r.routeName))),
                // Not in the list? Make one: this opens Setup › Route.
                if (widget.editing == null)
                const DropdownMenuItem(
                  value: _NewTemplateCard.newRoute,
                  child: Row(children: [
                    Icon(Icons.add_road, size: 18, color: AppColors.primary),
                    SizedBox(width: AppSpacing.sm),
                    Text('Add a new route…',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
              onChanged: (v) {
                if (v == _NewTemplateCard.newRoute) {
                  // Leave the choice as it was; the new route is made in Setup.
                  setState(() => _epoch++);
                  widget.onNewRoute();
                  return;
                }
                setState(() => _routeId = v);
              },
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
                      fontWeight: FontWeight.w700,
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAction))
                  : Icon(widget.editing == null ? Icons.add : Icons.check),
              label: Text(widget.editing == null ? 'Add trip schedule' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit / Delete at the end of a schedule's row: a word beside the icon,
/// so a Terminal Manager does not have to guess what the icon does.
class _RowAction extends StatelessWidget {
  const _RowAction({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: danger ? AppColors.danger : AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 36),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

/// Trip Schedules as a page of the Trips area (11 Nov; "Timetable" until
/// 12 Nov): beside the trips it makes and the button that posts them.
class TimetablePage extends StatelessWidget {
  const TimetablePage({super.key, required this.onOpenRoute});

  /// A departure needs a route in service: opens Setup when none is.
  final VoidCallback onOpenRoute;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ScheduleScreen(onOpenRoute: onOpenRoute),
      );
}
