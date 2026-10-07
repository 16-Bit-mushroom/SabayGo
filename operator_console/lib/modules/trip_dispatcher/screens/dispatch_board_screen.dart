import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';
import '../../../core/design/tokens.dart';

/// Trip dispatch, as the backend actually models it.
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
          content: const Text('Special trip dispatched to the ground crew.'),
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
              Row(
                children: [
                  const Text(
                    'Trip Dispatch Command',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
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

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
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
      ('Departs', 13, true),
      ('Bookings', 12, true),
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

    const figures = TextStyle(
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
                    style: const TextStyle(
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
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            cell(1, Text(trip.plateNumber ?? '—', style: figures)),
            cell(2, Text(DateFormat.jm().format(trip.departureDatetime), style: figures)),
            cell(3, Text('${trip.totalBookings}/${trip.seatCapacity}', style: figures)),
            cell(
              4,
              // Token container/on pairs. "Scheduled" is not a warning --
              // nothing is wrong with it -- so it is info-blue.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: departed ? AppColors.primaryContainer : AppColors.infoContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  departed ? 'Departed' : 'Scheduled',
                  style: TextStyle(
                    color: departed ? AppColors.primary : AppColors.info,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final title = Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(children: [
            const Text("Today's Departures",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(width: AppSpacing.sm),
            if (trips.isNotEmpty)
              Text(trips.length == 1 ? '1 trip' : '${trips.length} trips',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        );
        if (trips.isEmpty) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            title,
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                  child: Text('No departures today. Generate trips from Schedules, or dispatch one here.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))),
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
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Dispatch Special Trip',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text(
              'An ad-hoc departure outside the regular schedule.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
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
                decoration: _fieldDecoration('Departure Time'),
                child: Text(_departureTime.format(context), style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Assign Van (optional)',
              _vans
                  .map((v) => DropdownMenuItem(
                      value: v.vanId, child: Text('${v.plateNumber} (${v.seatCapacity} seats)')))
                  .toList(),
              _vanId,
              (val) => setState(() => _vanId = val),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Assign Driver (optional)',
              _drivers.map((d) => DropdownMenuItem(value: d.userId, child: Text(d.fullName))).toList(),
              _driverId,
              (val) => setState(() => _driverId = val),
            ),
            const SizedBox(height: 16),
            _buildDropdown<String>(
              'Assign Conductor (optional)',
              _conductors.map((c) => DropdownMenuItem(value: c.userId, child: Text(c.fullName))).toList(),
              _conductorId,
              (val) => setState(() => _conductorId = val),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canDispatch() ? _dispatchTrip : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: AppColors.surface,
                  disabledBackgroundColor: AppColors.surfaceSunken,
                  disabledForegroundColor: AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _dispatching
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('Confirm Dispatch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
      style: const TextStyle(color: AppColors.textPrimary),
      value: currentValue,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
      );
}
