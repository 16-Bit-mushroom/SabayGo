import 'package:flutter/material.dart';
import '../../models/van_model.dart';
import '../../models/transit_node_model.dart';

class AddVanScreen extends StatefulWidget {
  final VanModel? existingVan; // Pass a van if editing, null if adding new

  const AddVanScreen({super.key, this.existingVan});

  @override
  State<AddVanScreen> createState() => _AddVanScreenState();
}

class _AddVanScreenState extends State<AddVanScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _plateCtrl;
  
  VanStatus _selectedStatus = VanStatus.active;
  
  // Mock master list of all terminals in the SabayGo network
  final List<TransitNodeModel> _allNodes = const [
    TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City'),
    TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City'),
    TransitNodeModel(id: 'n3', name: 'Digos City Terminal', area: 'Digos City'),
    TransitNodeModel(id: 'n4', name: 'General Santos Terminal', area: 'General Santos City'),
    TransitNodeModel(id: 'n5', name: 'Tagum City Terminal', area: 'Tagum City'),
  ];

  // Holds the IDs of the terminals this van is legally allowed to stop at
  List<String> _selectedNodeIds = [];

  @override
  void initState() {
    super.initState();
    _plateCtrl = TextEditingController(text: widget.existingVan?.plateNumber ?? '');
    if (widget.existingVan != null) {
      _selectedStatus = widget.existingVan!.status;
      _selectedNodeIds = List.from(widget.existingVan!.registeredRouteNodeIds);
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    super.dispose();
  }

  void _toggleNode(String nodeId, bool? isChecked) {
    setState(() {
      if (isChecked == true) {
        _selectedNodeIds.add(nodeId);
      } else {
        _selectedNodeIds.remove(nodeId);
      }
    });
  }

  void _saveVan() {
    if (_formKey.currentState!.validate()) {
      if (_selectedNodeIds.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A van must have at least 2 terminal stops (Origin and Destination).')),
        );
        return;
      }

      // TODO: Pass this data back to the ViewModel / Backend
      // final newVan = VanModel(
      //   id: widget.existingVan?.id ?? DateTime.now().toString(),
      //   plateNumber: _plateCtrl.text,
      //   registeredRouteNodeIds: _selectedNodeIds,
      //   status: _selectedStatus,
      // );
      
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingVan != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Van Details' : 'Register New Van', style: const TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('VAN IDENTIFICATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      
                      // Plate Number Input
                      TextFormField(
                        controller: _plateCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Plate Number (e.g. ABC-1234)',
                          prefixIcon: const Icon(Icons.directions_car_outlined, color: Colors.grey),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A859), width: 2)),
                        ),
                        validator: (val) => val == null || val.isEmpty ? 'Plate number is required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // Capacity (Read-Only based on our earlier decision)
                      TextFormField(
                        initialValue: '14 Seats (Standard UV Express)',
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Passenger Capacity',
                          prefixIcon: const Icon(Icons.event_seat_outlined, color: Colors.grey),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Status Dropdown
                      DropdownButtonFormField<VanStatus>(
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          labelText: 'Operational Status',
                          prefixIcon: const Icon(Icons.info_outline, color: Colors.grey),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: const [
                          DropdownMenuItem(value: VanStatus.active, child: Text('Active (Ready for Dispatch)')),
                          DropdownMenuItem(value: VanStatus.maintenance, child: Text('Under Maintenance')),
                          DropdownMenuItem(value: VanStatus.inactive, child: Text('Inactive')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStatus = val);
                        },
                      ),

                      const SizedBox(height: 32),
                      const Text('LTFRB REGISTERED ROUTE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Select all terminal nodes this van is legally permitted to stop at.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 12),
                      
                      // Route Selection List
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: _allNodes.map((node) {
                            final isSelected = _selectedNodeIds.contains(node.id);
                            return CheckboxListTile(
                              title: Text(node.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(node.area, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              value: isSelected,
                              activeColor: const Color(0xFF00A859),
                              onChanged: (val) => _toggleNode(node.id, val),
                              secondary: Icon(Icons.location_on, color: isSelected ? const Color(0xFFD9534F) : Colors.grey.shade400),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // --- Save Button ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saveVan,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00A859),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditing ? 'Save Changes' : 'Register Van', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}