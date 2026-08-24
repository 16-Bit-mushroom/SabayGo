import 'package:flutter/material.dart';
import '../../models/van_model.dart';
import '../../viewmodels/dispatcher/trip_schedule_viewmodel.dart';
import 'add_van_screen.dart';

class ManageFleetScreen extends StatefulWidget {
  const ManageFleetScreen({super.key});

  @override
  State<ManageFleetScreen> createState() => _ManageFleetScreenState();
}

class _ManageFleetScreenState extends State<ManageFleetScreen> {
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
          itemCount: _viewModel.fleetVans.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final van = _viewModel.fleetVans[index];
            final isActive = van.status == VanStatus.active;
            
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.directions_car, color: isActive ? const Color(0xFF2D2059) : Colors.grey),
                            const SizedBox(width: 12),
                            Text(van.plateNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'INACTIVE', 
                          style: TextStyle(color: isActive ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // --- Edit & Delete Actions ---
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        onSelected: (value) {
                          if (value == 'edit') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AddVanScreen(existingVan: van)));
                          } else if (value == 'delete') {
                            _viewModel.deleteVan(van.id);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Van removed from fleet.')));
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                          const PopupMenuItem(value: 'delete', child: Text('Remove Van', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  
                  // Van Specifics Row
                  Row(
                    children: [
                      _buildInfoChip(Icons.branding_watermark, van.brand),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.event_seat, '${van.capacity} Seats'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // CPC Case and Number Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.gavel_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CPC Case No: ${van.cpcCaseNumber}  •  CPC No: ${van.cpcNumber}', 
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500)
                        )
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddVanScreen()));
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Register New Van', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}