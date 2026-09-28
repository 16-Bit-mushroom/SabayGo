import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/driver_model.dart';

class AddDriverScreen extends StatefulWidget {
  final DriverModel? existingDriver;

  const AddDriverScreen({super.key, this.existingDriver});

  @override
  State<AddDriverScreen> createState() => _AddDriverScreenState();
}

class _AddDriverScreenState extends State<AddDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _licenseCtrl;
  late TextEditingController _cttmoCtrl;
  
  DateTime? _licenseExpiryDate;
  DriverStatus _selectedStatus = DriverStatus.active;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDriver;
    _nameCtrl = TextEditingController(text: d?.fullName ?? '');
    _contactCtrl = TextEditingController(text: d?.contactNumber ?? '');
    _licenseCtrl = TextEditingController(text: d?.professionalLicenseNo ?? '');
    _cttmoCtrl = TextEditingController(text: d?.cttmoIdNo ?? '');
    
    if (d != null) {
      _licenseExpiryDate = d.licenseExpiryDate;
      _selectedStatus = d.status;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _licenseCtrl.dispose();
    _cttmoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _licenseExpiryDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)), // Allow slightly expired for logging
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00A859)),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _licenseExpiryDate = date);
    }
  }

  void _saveDriver() {
    if (_formKey.currentState!.validate()) {
      if (_licenseExpiryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please set the license expiry date.')));
        return;
      }
      // TODO: Save to backend/ViewModel
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.existingDriver == null ? 'Driver Registered!' : 'Driver Details Updated!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingDriver != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Driver Details' : 'Register New Driver', style: const TextStyle(fontSize: 18, color: Colors.black87)),
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
                      // --- Personal Details ---
                      const Text('PERSONAL DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDeco('Full Name', Icons.person_outline),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _contactCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDeco('Contact Number', Icons.phone_outlined),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 32),

                      // --- Credentials ---
                      // --- Credentials ---
                      const Text('LOCAL COMPLIANCE & CREDENTIALS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),

                      // NEW: ID Photo Upload Box (Landscape for IDs)
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade400, size: 32),
                            const SizedBox(height: 8),
                            Text('Upload CTTMO ID Photo', style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _cttmoCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDeco('CTTMO ID Number', Icons.badge_outlined),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),

                      TextFormField(
                        controller: _licenseCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDeco('Professional License No.', Icons.drive_eta_outlined),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      InkWell(
                        onTap: _pickExpiryDate,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDeco('License Expiry Date', Icons.calendar_month_outlined),
                          child: Text(
                            _licenseExpiryDate == null 
                                ? 'Tap to select date' 
                                : DateFormat('MMMM dd, yyyy').format(_licenseExpiryDate!),
                            style: TextStyle(color: _licenseExpiryDate == null ? Colors.grey.shade600 : Colors.black87, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<DriverStatus>(
                        value: _selectedStatus,
                        decoration: _inputDeco('Employment Status', Icons.info_outline),
                        items: const [
                          DropdownMenuItem(value: DriverStatus.active, child: Text('Active (Ready for Dispatch)')),
                          DropdownMenuItem(value: DriverStatus.suspended, child: Text('Suspended')),
                          DropdownMenuItem(value: DriverStatus.inactive, child: Text('Inactive / Resigned')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStatus = val);
                        },
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
                  onPressed: _saveDriver,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00A859),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditing ? 'Save Changes' : 'Register Driver', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
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