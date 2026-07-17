import 'package:flutter/material.dart';

class EditDispatcherProfileScreen extends StatefulWidget {
  const EditDispatcherProfileScreen({super.key});

  @override
  State<EditDispatcherProfileScreen> createState() => _EditDispatcherProfileScreenState();
}

class _EditDispatcherProfileScreenState extends State<EditDispatcherProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers for the business/staff details
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _coopCtrl;
  late TextEditingController _terminalCtrl;
  
  String _selectedRole = 'Dispatcher';

  @override
  void initState() {
    super.initState();
    // In a real app, you would initialize these with the current user's data
    // if they are editing an existing profile, or leave blank if it's a fresh sign-up.
    _nameCtrl = TextEditingController(text: 'Adonis T. Zuma');
    _phoneCtrl = TextEditingController(text: '0917-123-4567');
    _coopCtrl = TextEditingController(text: 'Davao UV Express Cooperative');
    _terminalCtrl = TextEditingController(text: 'Ecoland Terminal');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _coopCtrl.dispose();
    _terminalCtrl.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      // Simulate network request to ASP.NET Core backend
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terminal Profile Updated Successfully'),
            backgroundColor: Color(0xFF00A859), // Success Green
          ),
        );
        Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Manage Staff Profile', style: TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Avatar Upload Section ---
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF2D2059).withOpacity(0.1),
                        child: const Icon(Icons.badge_outlined, size: 40, color: Color(0xFF2D2059)),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2059),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                const Text('PERSONAL DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 16),

                _buildLabel('Full Name*'),
                _buildTextField(controller: _nameCtrl, hint: 'Enter your full name', icon: Icons.person_outline),
                const SizedBox(height: 20),

                _buildLabel('Contact Number*'),
                _buildTextField(controller: _phoneCtrl, hint: 'e.g. 0917-123-4567', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 32),

                const Text('OPERATIONAL ASSIGNMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 16),

                // --- RBAC Role Selection ---
                _buildLabel('System Role*'),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  icon: Icon(Icons.expand_more, color: Colors.grey.shade500),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined, color: Colors.grey.shade500, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.black, width: 1.5)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Operator', child: Text('Franchise Operator', style: TextStyle(fontWeight: FontWeight.w600))),
                    DropdownMenuItem(value: 'Dispatcher', child: Text('Terminal Dispatcher', style: TextStyle(fontWeight: FontWeight.w600))),
                  ],
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedRole == 'Operator' 
                    ? 'Operators have full access to manage fleet, crew, and view financial analytics.'
                    : 'Dispatchers can manage daily trip schedules and passenger manifests.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                const SizedBox(height: 20),

                _buildLabel('Cooperative Name*'),
                _buildTextField(controller: _coopCtrl, hint: 'Enter your Transport Cooperative', icon: Icons.business_outlined),
                const SizedBox(height: 20),

                _buildLabel('Assigned Terminal*'),
                _buildTextField(controller: _terminalCtrl, hint: 'Enter your physical terminal location', icon: Icons.location_on_outlined),
                const SizedBox(height: 40),

                // --- Save Button ---
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2D2059),
                      disabledBackgroundColor: const Color(0xFF2D2059).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const SizedBox(
                          height: 20, 
                          width: 20, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : const Text(
                          'Save Profile Changes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, required IconData icon, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontWeight: FontWeight.w600),
      validator: (val) => val == null || val.isEmpty ? 'This field is required' : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal),
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.black, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
      ),
    );
  }
}