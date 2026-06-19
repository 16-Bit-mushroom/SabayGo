import 'package:flutter/material.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUserData;

  const EditProfileScreen({
    Key? key,
    required this.currentUserData,
  }) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyPhoneController;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.currentUserData['firstName'] ?? '');
    _lastNameController = TextEditingController(text: widget.currentUserData['lastName'] ?? '');
    _emailController = TextEditingController(text: widget.currentUserData['email'] ?? '');
    _phoneController = TextEditingController(text: widget.currentUserData['phoneNumber'] ?? '');
    _emergencyNameController = TextEditingController(text: widget.currentUserData['emergencyContactName'] ?? '');
    _emergencyPhoneController = TextEditingController(text: widget.currentUserData['emergencyContactPhone'] ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      // TODO: Connect to SqliteUserRepository to execute UPDATE
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Profile validated and ready to save! ✓"),
          backgroundColor: const Color(0xFF00A859),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Edit Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("PERSONAL INFORMATION"),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("First Name"),
                        TextFormField(
                          controller: _firstNameController,
                          validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                          decoration: _inputDecoration(Icons.person_outline),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("Last Name"),
                        TextFormField(
                          controller: _lastNameController,
                          validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                          decoration: _inputDecoration(null), // No icon to save space
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _buildInputLabel("University Email"),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email is required";
                  if (!value.endsWith(".edu.ph")) return "Must be a valid .edu.ph address";
                  return null;
                },
                decoration: _inputDecoration(Icons.school_outlined),
              ),
              const SizedBox(height: 20),

              _buildInputLabel("Phone Number"),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (value) {
                   if (value == null || value.isEmpty) return "Required";
                   // Basic validation matching the Python Value Object logic
                   final clean = value.replaceAll(' ', '');
                   if (!(clean.startsWith('09') && clean.length == 11) && 
                       !(clean.startsWith('+639') && clean.length == 13)) {
                     return "Valid PH format required (e.g. 09123456789)";
                   }
                   return null;
                },
                decoration: _inputDecoration(Icons.phone_outlined),
              ),
              const SizedBox(height: 32),

              _buildSectionHeader("EMERGENCY CONTACT"),
              _buildInputLabel("Contact Name"),
              TextFormField(
                controller: _emergencyNameController,
                validator: (value) => value == null || value.trim().isEmpty ? "Required for safety" : null,
                decoration: _inputDecoration(Icons.health_and_safety_outlined),
              ),
              const SizedBox(height: 20),

              _buildInputLabel("Contact Phone Number"),
              TextFormField(
                controller: _emergencyPhoneController,
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.length < 10 ? "Valid number required" : null,
                decoration: _inputDecoration(Icons.phone_in_talk_outlined),
              ),
              const SizedBox(height: 40),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2059),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text("Save Changes", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12, letterSpacing: 1.2)),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
    );
  }

  InputDecoration _inputDecoration(IconData? icon) {
    return InputDecoration(
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade500) : null,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2D2059), width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
    );
  }
}