import 'package:flutter/material.dart';

class FleetRosterScreen extends StatefulWidget {
  const FleetRosterScreen({super.key});

  @override
  State<FleetRosterScreen> createState() => _FleetRosterScreenState();
}

class _FleetRosterScreenState extends State<FleetRosterScreen> {
  // Mock Data mapped from your Vans table
  final List<Map<String, dynamic>> _vans = [
    {'vanId': 'V-001', 'plate': 'ABC-1234', 'model': 'Toyota Hiace', 'capacity': 14, 'status': 'Active'},
    {'vanId': 'V-002', 'plate': 'DEF-5555', 'model': 'Nissan Urvan', 'capacity': 18, 'status': 'Active'},
    {'vanId': 'V-003', 'plate': 'GHI-7777', 'model': 'Toyota Hiace', 'capacity': 14, 'status': 'Maintenance'},
    {'vanId': 'V-004', 'plate': 'JKL-8888', 'model': 'Foton Traveller', 'capacity': 16, 'status': 'Active'},
  ];

  // Mock Data mapped from your Drivers table
  final List<Map<String, dynamic>> _drivers = [
    {'driverId': 'D-101', 'name': 'Juan Dela Cruz', 'license': 'N01-22-3333', 'status': 'Active', 'flag': 'Clear'},
    {'driverId': 'D-102', 'name': 'Pedro Penduko', 'license': 'N02-44-5555', 'status': 'Active', 'flag': 'Clear'},
    {'driverId': 'D-103', 'name': 'Mario Reyes', 'license': 'N03-66-7777', 'status': 'Suspended', 'flag': '₱300 Unremitted'},
    {'driverId': 'D-104', 'name': 'Cardo Dalisay', 'license': 'N04-88-9999', 'status': 'Active', 'flag': 'Clear'},
  ];

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
                'Fleet & Crew Roster',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: isDesktop 
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
    return _buildCardWrapper(
      title: 'Active Fleet (Vans)',
      icon: Icons.directions_car_filled_outlined,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
        dataRowMinHeight: 50,
        dataRowMaxHeight: 60,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
        columns: const [
          DataColumn(label: Text('Plate No.')),
          DataColumn(label: Text('Model')),
          DataColumn(label: Text('Seats')),
          DataColumn(label: Text('Status')),
        ],
        rows: _vans.map((van) {
          final isActive = van['status'] == 'Active';
          return DataRow(
            cells: [
              DataCell(Text(van['plate'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
              DataCell(Text(van['model'], style: const TextStyle(color: Colors.white70))),
              DataCell(Text(van['capacity'].toString(), style: const TextStyle(color: Colors.white70))),
              DataCell(_buildStatusChip(van['status'], isActive)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDriversTable() {
    return _buildCardWrapper(
      title: 'Registered Crew (Drivers)',
      icon: Icons.badge_outlined,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
        dataRowMinHeight: 50,
        dataRowMaxHeight: 60,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
        columns: const [
          DataColumn(label: Text('Driver Name')),
          DataColumn(label: Text('License ID')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('System Flag')),
        ],
        rows: _drivers.map((driver) {
          final isActive = driver['status'] == 'Active';
          final hasFlag = driver['flag'] != 'Clear';
          return DataRow(
            cells: [
              DataCell(Text(driver['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
              DataCell(Text(driver['license'], style: const TextStyle(color: Colors.white70))),
              DataCell(_buildStatusChip(driver['status'], isActive)),
              DataCell(
                Text(
                  driver['flag'], 
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasFlag ? Theme.of(context).colorScheme.error : const Color(0xFFA3BE8C),
                  )
                )
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCardWrapper({required String title, required IconData icon, required Widget child}) {
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
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
        )
      ),
      child: Text(
        text, 
        style: TextStyle(
          color: isPositive ? const Color(0xFFA3BE8C) : const Color(0xFFEBCB8B), 
          fontSize: 12, 
          fontWeight: FontWeight.bold
        )
      ),
    );
  }
}