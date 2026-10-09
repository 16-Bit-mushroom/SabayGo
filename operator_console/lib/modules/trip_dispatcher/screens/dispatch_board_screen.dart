import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';

/// Special Trips: trip dispatch, as the backend actually models it.
///
/// Regular departures are materialised from schedule templates
/// (`/config/trips/generate`, run on a schedule) -- there is no "pick an
/// origin and destination and go" flow for those. What a cooperative
/// administrator can dispatch by hand is an ad-hoc departure outside that
/// schedule (`/config/trips/special`): a route, a van, a crew, a time.
/// That is what this form creates.
class DispatchBoardScreen extends StatefulWidget {
  const DispatchBoardScreen({super.key});

  @override
  State<DispatchBoardScreen> createState() => _DispatchBoardScreenState();
}

class _DispatchBoardScreenState extends State<DispatchBoardScreen> {
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();
  late final FleetRepository _fleet = context.read<FleetRepository>();

  List<TripBoardRow>? _trips;
  List<RouteSummary> _routes = [];
  List<Van> _vans = [];
  List<StaffMember> _drivers = [];
  List<StaffMember> _conductors = [];
  bool _loading = true;
  String? _error;

  String? _routeId;
  String? _vanId;
  String? _driverId;
  String? _conductorId;
  TimeOfDay _departureTime = TimeOfDay.now();
  bool _dispatching = false;
  final _rowsScroll = ScrollController();

  @override
  void dispose() {
    _rowsScroll.dispose();
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
        _dispatch.todaysTrips(),
        _dispatch.listRoutes(),
        _fleet.listVans(),
        _fleet.listCrew(role: 'driver'),
        _fleet.listCrew(role: 'conductor'),
      ]);
      if (!mounted) return;
      setState(() {
        _trips = results[0] as List<TripBoardRow>;
        _routes = results[1] as List<RouteSummary>;
        _vans = (results[2] as List<Van>).where((v) => v.operationalStatus == 'active').toList();
        _drivers =
            (results[3] as List<StaffMember>).where((s) => s.employmentStatus == 'active').toList();
        _conductors =
            (results[4] as List<StaffMember>).where((s) => s.employmentStatus == 'active').toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _canDispatch() => _routeId != null && !_dispatching;

  Future<void> _dispatchTrip() async {
    if (_routeId == null) return;
    setState(() => _dispatching = true);
    try {
      final now = DateTime.now();
      var departure = DateTime(
        now.year, now.month, now.day, _departureTime.hour, _departureTime.minute,
      );
      if (departure.isBefore(now)) departure = departure.add(const Duration(days: 1));

      await _dispatch.createSpecialTrip(
        routeId: _routeId!,
        departureDatetime: departure,
        vanId: _vanId,
        driverId: _driverId,
        conductorId: _conductorId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Special trip added. It is on the Trips page now.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _routeId = null;
        _vanId = null;
        _driverId = null;
        _conductorId = null;
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _dispatching = false);
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
                title: 'Special Trips',
                description: 'Add an extra trip that is not on the Timetable -- for a rush hour '
                    'or a replacement van. Today\'s departures are listed for reference.',
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
                                  Expanded(flex: 3, child: _buildTripsGrid()),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 2, child: _buildDispatchForm()),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildDispatchForm(),
                                    const SizedBox(height: 24),
                                    _buildTripsGrid(),
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

  /// Today's departures: full width, headings pinned.
  ///
  /// Same flex table as Revenue, Schedules and Audits, for the same reason:
  /// a [DataTable] is only as wide as its columns, so its heading strip
  /// stopped at "Status" while the card ran on to the right. The card also
  /// shrinks to its rows now instead of standing full height with a blank
  /// band at the bottom.
  Widget _buildTripsGrid() {
    final trips = _trips ?? [];
    const columns = <(String, int, bool)>[
      ('Route', 26, false),
      ('Van', 13, false),
      ('Leaves at', 13, true),
      ('Seats booked', 14, true),
      ('Status', 15, false),
    ];
    const minWidth = 560.0;

    Widget cell(int i, Widget child) {
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

    final figures = TextStyle(
      color: AppColors.textPrimary,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget heading() => Container(
          height: 44,
          color: AppColors.surfaceSunken,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(children: [
            for (var i = 0; i < columns.length; i++)
              cell(
                i,
                Text(columns[i].$1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
              ),
          ]),
        );

    Widget row(TripBoardRow trip) {
      final departed = trip.hasDeparted;
      return SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(children: [
            cell(
              0,
              Text(trip.routeName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            cell(1, Text(trip.plateNumber ?? '—', style: figures)),
            cell(2, Text(DateFormat.jm().format(trip.departureDatetime), style: figures)),
            cell(3, Text('${trip.totalBookings}/${trip.seatCapacity}', style: figures)),
            cell(
              4,
              // The same words and colours as the Trips page.
              StatusBadge.trip(departed ? 'departed' : 'scheduled'),
            ),
          ]),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final title = Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(children: [
            Text("Today's departures", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            if (trips.isNotEmpty)
              Text(trips.length == 1 ? '1 trip' : '${trips.length} trips',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        );
        if (trips.isEmpty) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            title,
            const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No trips today',
              hint: 'Create them from the Timetable, or add a special trip with the form.',
            ),
          ]);
        }

        final width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
        // Beside the form the height is bounded: shrink to the rows, scroll
        // past them. Stacked on a narrow screen it sits inside the page's
        // own scroll view, where a flexible list has no height to fill.
        final body = c.hasBoundedHeight
            ? Flexible(
                child: Scrollbar(
                  controller: _rowsScroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _rowsScroll,
                    shrinkWrap: true,
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => row(trips[i]),
                  ),
                ),
              )
            : Column(children: [
                for (var i = 0; i < trips.length; i++) ...[
                  if (i > 0) const Divider(),
                  row(trips[i]),
                ],
              ]);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: c.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, heading(), const Divider(), body],
            ),
          ),
        );
      }),
    );
  }


  Widget _buildDispatchForm() {
    return Panel(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add a special trip', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Only the route is needed. Van and crew can be added later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xxl),
            _buildDropdown<String>(
              'Route',
              _routes.map((r) => DropdownMenuItem(value: r.routeId, child: Text(r.routeName))).toList(),
              _routeId,
              (val) => setState(() => _routeId = val),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _departureTime);
                if (picked != null) setState(() => _departureTime = picked);
              },
              child: InputDecorator(
                decoration: _fieldDecoration('Leaves at').copyWith(
                  // The form books the next occurrence of this time.
                  helperText: 'If this time has already passed, the trip is set for tomorrow.',
                ),
                child: Text(_departureTime.format(context), style: TextStyle(color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Van (optional)',
              _vans
                  .map((v) => DropdownMenuItem(
                      value: v.vanId, child: Text('${v.plateNumber} (${v.seatCapacity} seats)')))
                  .toList(),
              _vanId,
              (val) => setState(() => _vanId = val),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Driver (optional)',
              _drivers.map((d) => DropdownMenuItem(value: d.userId, child: Text(d.fullName))).toList(),
              _driverId,
              (val) => setState(() => _driverId = val),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Conductor (optional)',
              _conductors.map((c) => DropdownMenuItem(value: c.userId, child: Text(c.fullName))).toList(),
              _conductorId,
              (val) => setState(() => _conductorId = val),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canDispatch() ? _dispatchTrip : null,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                icon: _dispatching
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onFill))
                    : const Icon(Icons.add),
                label: const Text('Add special trip'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(
      String label, List<DropdownMenuItem<T>> items, T? currentValue, void Function(T?) onChanged) {
    return DropdownButtonFormField<T>(
      decoration: _fieldDecoration(label),
      dropdownColor: AppColors.surfaceSunken,
      style: TextStyle(color: AppColors.textPrimary),
      value: currentValue,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textMuted),
      );
}
