import 'package:flutter/material.dart';
import '../../models/van_model.dart';
import '../../models/transit_node_model.dart';

class AddVanScreen extends StatefulWidget {
  final VanModel? existingVan; 

  const AddVanScreen({super.key, this.existingVan});

  @override
  State<AddVanScreen> createState() => _AddVanScreenState();
}

class _AddVanScreenState extends State<AddVanScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _plateCtrl;
  late TextEditingController _cpcCtrl;
  late TextEditingController _cpcCaseCtrl;
  late TextEditingController _brandCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _capacityCtrl;
  
  VanStatus _selectedStatus = VanStatus.active;
  List<String> _selectedNodeIds = [];

  final List<TransitNodeModel> _allNodes = const [
    TransitNodeModel(id: 'n1', name: 'Ecoland Terminal', area: 'Davao City'),
    TransitNodeModel(id: 'n2', name: 'Cotabato City Terminal', area: 'Cotabato City'),
    TransitNodeModel(id: 'n3', name: 'Digos City Terminal', area: 'Digos City'),
    TransitNodeModel(id: 'n4', name: 'General Santos Terminal', area: 'General Santos City'),
    TransitNodeModel(id: 'n5', name: 'Tagum City Terminal', area: 'Tagum City'),
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.existingVan; // safely assigned here
    
    _plateCtrl = TextEditingController(text: v?.plateNumber ?? '');
    _cpcCtrl = TextEditingController(text: v?.cpcNumber ?? '');
    _cpcCaseCtrl = TextEditingController(text: v?.cpcCaseNumber ?? '');
    _brandCtrl = TextEditingController(text: v?.brand ?? '');
    _modelCtrl = TextEditingController(text: v?.model ?? '');
    _colorCtrl = TextEditingController(text: v?.color ?? '');
    _capacityCtrl = TextEditingController(text: v?.capacity.toString() ?? '14');
    
    if (v != null) {
      _selectedStatus = v.status;
      _selectedNodeIds = List.from(v.registeredRouteNodeIds);
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _cpcCtrl.dispose();
    _cpcCaseCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  void _saveVan() {
    if (_formKey.currentState!.validate()) {
      if (_selectedNodeIds.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least 2 terminal stops (Origin & Destination).')),
        );
        return;
      }

      // TODO: Save to backend
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.existingVan == null ? 'Van Registered!' : 'Van Details Updated!')),
      );
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
      // --- ADDED SafeArea HERE ---
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
                      // --- Photos Section ---
                      const Text('VEHICLE PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildPhotoBox('Front'),
                          _buildPhotoBox('Back'),
                          _buildPhotoBox('Left'),
                          _buildPhotoBox('Right'),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- Identification Section ---
                      const Text('VEHICLE IDENTIFICATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      
                      TextFormField(
                        controller: _plateCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDeco('Plate Number (e.g. ABC-1234)', Icons.directions_car_outlined),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cpcCaseCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _inputDeco('CPC Case No. (YY-NNNNN)', Icons.gavel_outlined),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _cpcCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _inputDeco('CPC Number', Icons.confirmation_number_outlined),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _brandCtrl,
                              decoration: _inputDeco('Brand (e.g. Toyota)', Icons.branding_watermark_outlined),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _modelCtrl,
                              decoration: _inputDeco('Model (e.g. Hiace)', Icons.directions_car),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _colorCtrl,
                              decoration: _inputDeco('Color', Icons.color_lens_outlined),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _capacityCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _inputDeco('Seat Cap.', Icons.event_seat_outlined),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<VanStatus>(
                        value: _selectedStatus,
                        decoration: _inputDeco('Operational Status', Icons.info_outline),
                        items: const [
                          DropdownMenuItem(value: VanStatus.active, child: Text('Active (Ready)')),
                          DropdownMenuItem(value: VanStatus.maintenance, child: Text('Under Maintenance')),
                          DropdownMenuItem(value: VanStatus.inactive, child: Text('Inactive')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStatus = val);
                        },
                      ),

                      const SizedBox(height: 32),

                      // --- Routes Section ---
                      const Text('LTFRB REGISTERED ROUTE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: _allNodes.map((node) {
                            final isSelected = _selectedNodeIds.contains(node.id);
                            return CheckboxListTile(
                              title: Text(node.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(node.area, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              value: isSelected,
                              activeColor: const Color(0xFF00A859),
                              onChanged: (val) {
                                setState(() {
                                  val == true ? _selectedNodeIds.add(node.id) : _selectedNodeIds.remove(node.id);
                                });
                              },
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
              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
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

  Widget _buildPhotoBox(String label) {
    return Column(
      children: [
        Container(
          height: 60,
          width: 60,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
          child: Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade400, size: 24),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
      ],
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A859), width: 2)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}