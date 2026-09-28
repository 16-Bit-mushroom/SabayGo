import 'package:flutter/material.dart';
import 'manage_fleet_screen.dart';
import 'add_driver_screen.dart'; 
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
      length: 3, // Increased from 2 to 3 to accommodate Conductors
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true, // Allows tabs to fit neatly on smaller screens
              indicatorColor: const Color(0xFF00A859),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00A859),
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'Registered Vans'),
                Tab(text: 'Verified Drivers'),
                Tab(text: 'Conductors'), // New Tab Added
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                ManageFleetScreen(), 
                _DriverListTab(), 
                _ConductorListTab(), // The New Conductor UI
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
                  
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'CTTMO: ${driver.cttmoIdNo}', 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.drive_eta_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Lic: ${driver.professionalLicenseNo}', 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                overflow: TextOverflow.ellipsis, 
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

// --- NEW: The Conductor List Tab (Aligned with Table 20) ---
class _ConductorListTab extends StatelessWidget {
  const _ConductorListTab();

  // Mock data aligned exactly with the new Conductors database schema
  final List<Map<String, dynamic>> mockConductors = const [
    {
      'firstName': 'Adonis',
      'middleName': 'T.',
      'lastName': 'Zuma',
      'birthDate': '1985-10-12', // YYYY-MM-DD
      'phoneNumber': '+63 917 123 4567',
      'gender': 'Male',
      'homeAddress': 'Matina Crossing, Davao City',
      'profilePicUrl': null,
      'employmentStatus': 'Active',
    },
    {
      'firstName': 'Elena',
      'middleName': 'V.',
      'lastName': 'Reyes',
      'birthDate': '1992-03-25',
      'phoneNumber': '+63 918 987 6543',
      'gender': 'Female',
      'homeAddress': 'Ecoland Drive, Davao City',
      'profilePicUrl': null,
      'employmentStatus': 'Inactive',
    },
  ];

  // Helper method to dynamically calculate age from BirthDate
  int _calculateAge(String birthDateString) {
    DateTime birthDate = DateTime.parse(birthDateString);
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: mockConductors.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final conductor = mockConductors[index];
            final isActive = conductor['employmentStatus'] == 'Active';
            final age = _calculateAge(conductor['birthDate']);
            // Combine first and last name for display
            final fullName = '${conductor['firstName']} ${conductor['lastName']}';
            
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
                      // --- Profile Picture ---
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          image: conductor['profilePicUrl'] != null
                              ? DecorationImage(
                                  image: NetworkImage(conductor['profilePicUrl']),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: conductor['profilePicUrl'] == null
                            ? Icon(Icons.person, color: Colors.grey.shade400, size: 32)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      
                      // --- Conductor Name & Status ---
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                conductor['employmentStatus'].toUpperCase(), 
                                style: TextStyle(color: isActive ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
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
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action tapped (Mock UI)')));
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                          const PopupMenuItem(value: 'delete', child: Text('Remove Conductor', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  
                  // --- Demographics Row (Age, Gender, Phone) ---
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.phone_android, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                conductor['phoneNumber'], 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${conductor['gender']} • $age yrs', 
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // --- Home Address Row ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.home_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          conductor['homeAddress'], 
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        
        // --- Register Button ---
        Positioned(
          bottom: 20,
          right: 20,
          left: 20,
          child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Navigate to Add Conductor (Mock UI)')));
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.person_add, size: 20),
            label: const Text('Register Conductor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}