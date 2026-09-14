import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/fleet_repository.dart';

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
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTripsGrid() {
    final trips = _trips ?? [];
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Today's Departures",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            if (trips.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                    child: Text('No departures today.', style: TextStyle(color: Colors.white54))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
                    dataRowMinHeight: 50,
                    dataRowMaxHeight: 60,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
                    columns: const [
                      DataColumn(label: Text('Route')),
                      DataColumn(label: Text('Van')),
                      DataColumn(label: Text('Departs')),
                      DataColumn(label: Text('Bookings')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: trips.map((trip) {
                      final departed = trip.hasDeparted;
                      return DataRow(
                        cells: [
                          DataCell(Text(trip.routeName,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                          DataCell(Text(trip.plateNumber ?? '—',
                              style: const TextStyle(color: Colors.white70))),
                          DataCell(Text(DateFormat.jm().format(trip.departureDatetime),
                              style: const TextStyle(color: Colors.white))),
                          DataCell(Text('${trip.totalBookings}/${trip.seatCapacity}',
                              style: const TextStyle(color: Colors.white70))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: (departed ? const Color(0xFF88C0D0) : const Color(0xFFEBCB8B))
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: departed ? const Color(0xFF88C0D0) : const Color(0xFFEBCB8B)),
                              ),
                              child: Text(
                                departed ? 'Departed' : 'Scheduled',
                                style: TextStyle(
                                  color: departed ? const Color(0xFF88C0D0) : const Color(0xFFEBCB8B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            const Text(
              'An ad-hoc departure outside the regular schedule.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
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
                child: Text(_departureTime.format(context), style: const TextStyle(color: Colors.white)),
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
                  foregroundColor: const Color(0xFF151923),
                  disabledBackgroundColor: const Color(0xFF2C3244),
                  disabledForegroundColor: Colors.white54,
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
      dropdownColor: const Color(0xFF2C3244),
      style: const TextStyle(color: Colors.white),
      value: currentValue,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF151923),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );
}
