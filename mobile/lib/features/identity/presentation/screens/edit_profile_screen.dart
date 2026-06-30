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
  late TextEditingController _middleNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyPhoneController;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.currentUserData['firstName'] ?? '');
    _lastNameController = TextEditingController(text: widget.currentUserData['lastName'] ?? '');
    _middleNameController = TextEditingController(text: widget.currentUserData['middleName'] ?? '');
    _emailController = TextEditingController(text: widget.currentUserData['email'] ?? '');
    _phoneController = TextEditingController(text: widget.currentUserData['phoneNumber'] ?? '');
    _emergencyNameController = TextEditingController(text: widget.currentUserData['emergencyContactName'] ?? '');
    _emergencyPhoneController = TextEditingController(text: widget.currentUserData['emergencyContactPhone'] ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
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
        title: const Text("Edit Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        // TIGHTENED: Reduced outer padding from 24 to 16
        padding: const EdgeInsets.all(16.0),
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
                  const SizedBox(width: 12), // TIGHTENED
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("Last Name"),
                        TextFormField(
                          controller: _lastNameController,
                          validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                          decoration: _inputDecoration(null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12), // TIGHTENED
              
              _buildInputLabel("Middle Name (Optional)"),
              TextFormField(
                controller: _middleNameController,
                decoration: _inputDecoration(null),
              ),
              const SizedBox(height: 24), // TIGHTENED

              _buildSectionHeader("CONTACT INFORMATION"),
              _buildInputLabel("Email Address"),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email is required";
                  if (!value.contains("@") || !value.contains(".")) return "Must be a valid email address";
                  return null;
                },
                decoration: _inputDecoration(Icons.email_outlined),
              ),
              const SizedBox(height: 12), // TIGHTENED

              _buildInputLabel("Phone Number"),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (value) {
                   if (value == null || value.isEmpty) return "Required";
                   final clean = value.replaceAll(' ', '');
                   if (!(clean.startsWith('09') && clean.length == 11) && 
                       !(clean.startsWith('+639') && clean.length == 13)) {
                     return "Valid PH format required";
                   }
                   return null;
                },
                decoration: _inputDecoration(Icons.phone_outlined),
              ),
              const SizedBox(height: 24), // TIGHTENED

              _buildSectionHeader("EMERGENCY CONTACT"),
              _buildInputLabel("Contact Name"),
              TextFormField(
                controller: _emergencyNameController,
                validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                decoration: _inputDecoration(Icons.health_and_safety_outlined),
              ),
              const SizedBox(height: 12), // TIGHTENED

              _buildInputLabel("Contact Phone Number"),
              TextFormField(
                controller: _emergencyPhoneController,
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.length < 10 ? "Valid number required" : null,
                decoration: _inputDecoration(Icons.phone_in_talk_outlined),
              ),
              const SizedBox(height: 28), // TIGHTENED

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 48, // TIGHTENED: Reduced from 56 to 48
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2059),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Slightly tighter radius
                    elevation: 0,
                  ),
                  child: const Text("Save Changes", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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
      // TIGHTENED: Reduced bottom padding from 16 to 8
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11, letterSpacing: 1.0)),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      // TIGHTENED: Reduced bottom padding from 8 to 4
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87)),
    );
  }

  InputDecoration _inputDecoration(IconData? icon) {
    return InputDecoration(
      // TIGHTENED: Reduced icon size slightly to match new compact fields
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade500, size: 20) : null,
      filled: true,
      fillColor: Colors.grey.shade50,
      // TIGHTENED: Drastically reduced vertical padding inside the text box
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2D2059), width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
    );
  }
}