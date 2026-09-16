import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/profile_viewmodel.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _emerNameCtrl;
  late TextEditingController _emerRelationCtrl;
  late TextEditingController _emerPhoneCtrl;

  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _changingPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<ProfileViewModel>().currentUser!;
    _firstNameCtrl = TextEditingController(text: user.firstName);
    _lastNameCtrl = TextEditingController(text: user.lastName);
    _phoneCtrl = TextEditingController(text: user.phoneNumber ?? '');
    _addressCtrl = TextEditingController(text: user.address ?? '');
    _emerNameCtrl = TextEditingController(text: user.emergencyContactName ?? '');
    _emerRelationCtrl = TextEditingController(text: user.emergencyContactRelation ?? '');
    _emerPhoneCtrl = TextEditingController(text: user.emergencyContactPhone ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _emerNameCtrl.dispose();
    _emerRelationCtrl.dispose();
    _emerPhoneCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final message = await context.read<ProfileViewModel>().updateProfile(
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          phoneNumber: _phoneCtrl.text.trim(),
          homeAddress: _addressCtrl.text.trim(),
          emergencyContactName: _emerNameCtrl.text.trim(),
          emergencyContactRelation: _emerRelationCtrl.text.trim(),
          emergencyContactNumber: _emerPhoneCtrl.text.trim(),
          currentPassword: _changingPassword ? _currentPasswordCtrl.text : null,
          newPassword: _changingPassword ? _newPasswordCtrl.text : null,
        );

    if (!mounted) return;
    if (message != null) {
      setState(() {
        _saving = false;
        _error = message;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<ProfileViewModel>().currentUser!;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
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
                      Center(
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFF2D2059),
                          child: Text(
                            user.initials,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const Text('PERSONAL DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      _buildTextField('First Name', _firstNameCtrl, Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildTextField('Last Name', _lastNameCtrl, Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildTextField('Phone Number', _phoneCtrl, Icons.phone_outlined),
                      const SizedBox(height: 16),
                      _buildTextField('Email', TextEditingController(text: user.email), Icons.email_outlined, enabled: false, required: false),
                      const SizedBox(height: 16),
                      _buildTextField('Home Address', _addressCtrl, Icons.home_work_outlined, required: false),

                      const SizedBox(height: 32),
                      const Text('EMERGENCY CONTACT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      _buildTextField('Contact Name', _emerNameCtrl, Icons.health_and_safety_outlined, required: false),
                      const SizedBox(height: 16),
                      _buildTextField('Relation', _emerRelationCtrl, Icons.people_outline, required: false),
                      const SizedBox(height: 16),
                      _buildTextField('Contact Phone', _emerPhoneCtrl, Icons.phone_outlined, required: false),

                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('CHANGE PASSWORD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Switch(
                            value: _changingPassword,
                            activeThumbColor: const Color(0xFF00A859),
                            onChanged: (val) => setState(() => _changingPassword = val),
                          ),
                        ],
                      ),
                      if (_changingPassword) ...[
                        const SizedBox(height: 12),
                        _buildTextField('Current Password', _currentPasswordCtrl, Icons.lock_outline, obscure: true),
                        const SizedBox(height: 16),
                        _buildTextField('New Password (min. 8 characters)', _newPasswordCtrl, Icons.lock_reset, obscure: true),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00A859),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool required = true,
    bool enabled = true,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A859), width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: (val) {
        if (!required) return null;
        if (val == null || val.trim().isEmpty) return 'Required field';
        if (obscure && val.length < 8) return 'At least 8 characters';
        return null;
      },
    );
  }
}
