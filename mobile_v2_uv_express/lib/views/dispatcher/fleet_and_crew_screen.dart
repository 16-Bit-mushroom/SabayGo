import 'package:flutter/material.dart';
import 'manage_fleet_screen.dart';
import 'add_driver_screen.dart'; // Import the new form
import '../../models/driver_model.dart';
import '../../viewmodels/dispatcher/trip_schedule_viewmodel.dart';

class FleetAndCrewScreen extends StatefulWidget {
  const FleetAndCrewScreen({super.key});

  @override
  State<FleetAndCrewScreen> createState() => _FleetAndCrewScreenState();
}

class _FleetAndCrewScreenState extends State<FleetAndCrewScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              indicatorColor: const Color(0xFF00A859),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00A859),
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'Registered Vans'),
                Tab(text: 'Verified Drivers'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                ManageFleetScreen(), 
                _DriverListTab(), // The new Driver UI
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- The Driver List Tab ---
class _DriverListTab extends StatefulWidget {
  const _DriverListTab();

  @override
  State<_DriverListTab> createState() => _DriverListTabState();
}

class _DriverListTabState extends State<_DriverListTab> {
  final TripScheduleViewModel _viewModel = TripScheduleViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _viewModel.crewDrivers.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final driver = _viewModel.crewDrivers[index];
            final isActive = driver.status == DriverStatus.active;
            
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- NEW: CTTMO ID Thumbnail ---
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          image: driver.cttmoIdPhotoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(driver.cttmoIdPhotoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: driver.cttmoIdPhotoUrl == null
                            ? Icon(Icons.badge_outlined, color: Colors.grey.shade400)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      
                      // --- Driver Info ---
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isActive ? 'ACTIVE' : 'SUSPENDED', 
                                style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // --- Context Menu ---
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'edit') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AddDriverScreen(existingDriver: driver)));
                          } else if (value == 'delete') {
                            _viewModel.deleteDriver(driver.id);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver removed from active roster.')));
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                          const PopupMenuItem(value: 'delete', child: Text('Remove Driver', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  
                  // --- Credentials Row ---
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            // Wrapping Text in Expanded prevents the overflow
                            Expanded(
                              child: Text(
                                'CTTMO: ${driver.cttmoIdNo}', 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis, // Adds '...' if too long
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8), // Adds a tiny buffer between the columns
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.drive_eta_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            // Wrapping Text in Expanded prevents the overflow
                            Expanded(
                              child: Text(
                                'Lic: ${driver.professionalLicenseNo}', 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                overflow: TextOverflow.ellipsis, // Adds '...' if too long
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        
        Positioned(
          bottom: 20,
          right: 20,
          left: 20,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDriverScreen()));
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.person_add, size: 20),
            label: const Text('Register New Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}