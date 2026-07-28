import 'package:flutter/material.dart';

class DispatchBoardScreen extends StatefulWidget {
  const DispatchBoardScreen({super.key});

  @override
  State<DispatchBoardScreen> createState() => _DispatchBoardScreenState();
}

class _DispatchBoardScreenState extends State<DispatchBoardScreen> {
  // Mock Data: Active Trips
  final List<Map<String, dynamic>> _activeTrips = [
    {
      'tripId': 'TRP-101',
      'origin': 'Ecoland Terminal',
      'dest': 'Cotabato City',
      'van': 'ABC-1234',
      'driver': 'Juan Dela Cruz',
      'time': '05:30 AM',
      'status': 'En Route',
    },
    {
      'tripId': 'TRP-102',
      'origin': 'SM Ecoland',
      'dest': 'Digos City',
      'van': 'XYZ-9876',
      'driver': 'Pedro Penduko',
      'time': '06:00 AM',
      'status': 'Boarding',
    },
  ];

  // Mock Data: Available Resources for Dropdowns
  final List<String> _terminals = ['Ecoland Terminal', 'SM Ecoland', 'Cotabato City', 'Digos City', 'Kidapawan'];
  final List<String> _availableVans = ['DEF-5555 (14 Seats)', 'GHI-7777 (18 Seats)', 'JKL-8888 (14 Seats)'];
  final List<String> _availableDrivers = ['Mario Reyes', 'Lito Lapid', 'Cardo Dalisay'];

  // Form State
  String? _selectedOrigin;
  String? _selectedDest;
  String? _selectedVan;
  String? _selectedDriver;

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
              const Text(
                'Trip Dispatch Command',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: isDesktop 
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildActiveTripsGrid()),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: _buildDispatchForm()),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildDispatchForm(), // Form on top for mobile
                            const SizedBox(height: 24),
                            _buildActiveTripsGrid(),
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

  Widget _buildActiveTripsGrid() {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Trip ID')),
                DataColumn(label: Text('Route')),
                DataColumn(label: Text('Van')),
                DataColumn(label: Text('Driver')),
                DataColumn(label: Text('Departs')),
                DataColumn(label: Text('Status')),
              ],
              rows: _activeTrips.map((trip) {
                return DataRow(
                  cells: [
                    DataCell(Text(trip['tripId'], style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                    DataCell(Text('${trip['origin']} → ${trip['dest']}', style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(trip['van'], style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(trip['driver'], style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(trip['time'], style: const TextStyle(color: Colors.white))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: trip['status'] == 'En Route' 
                              ? const Color(0xFF88C0D0).withOpacity(0.2) // Nord Blue
                              : const Color(0xFFEBCB8B).withOpacity(0.2), // Nord Yellow
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: trip['status'] == 'En Route' ? const Color(0xFF88C0D0) : const Color(0xFFEBCB8B),
                          )
                        ),
                        child: Text(
                          trip['status'], 
                          style: TextStyle(
                            color: trip['status'] == 'En Route' ? const Color(0xFF88C0D0) : const Color(0xFFEBCB8B), 
                            fontSize: 12, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
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
            const Text('Dispatch New Trip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),
            
            _buildDropdown('Origin Terminal', _terminals, _selectedOrigin, (val) => setState(() => _selectedOrigin = val)),
            const SizedBox(height: 16),
            _buildDropdown('Destination Terminal', _terminals, _selectedDest, (val) => setState(() => _selectedDest = val)),
            const SizedBox(height: 16),
            _buildDropdown('Assign Van', _availableVans, _selectedVan, (val) => setState(() => _selectedVan = val)),
            const SizedBox(height: 16),
            _buildDropdown('Assign Driver', _availableDrivers, _selectedDriver, (val) => setState(() => _selectedDriver = val)),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canDispatch() ? _dispatchTrip : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: const Color(0xFF151923), // Dark text on light button
                  disabledBackgroundColor: const Color(0xFF2C3244),
                  disabledForegroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Confirm Dispatch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String? currentValue, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF151923), // Darker inset background
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
      dropdownColor: const Color(0xFF2C3244),
      style: const TextStyle(color: Colors.white),
      value: currentValue,
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
      onChanged: onChanged,
    );
  }

  bool _canDispatch() {
    return _selectedOrigin != null && 
           _selectedDest != null && 
           _selectedVan != null && 
           _selectedDriver != null &&
           _selectedOrigin != _selectedDest; // Prevent same origin/dest
  }

  void _dispatchTrip() {
    setState(() {
      _activeTrips.insert(0, {
        'tripId': 'TRP-${100 + _activeTrips.length + 1}', // Mock ID generation
        'origin': _selectedOrigin,
        'dest': _selectedDest,
        'van': _selectedVan!.split(' ')[0], // Extract just the plate
        'driver': _selectedDriver,
        'time': 'Now',
        'status': 'Boarding',
      });
      
      // Reset form
      _selectedOrigin = null;
      _selectedDest = null;
      _selectedVan = null;
      _selectedDriver = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Trip successfully dispatched to the ground crew!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}