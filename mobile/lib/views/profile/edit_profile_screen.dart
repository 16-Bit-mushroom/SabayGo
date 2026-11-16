import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/section_header.dart';
import '../../core/design/tokens.dart';
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
  late TextEditingController _emailCtrl;

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
    _emailCtrl = TextEditingController(text: user.email);
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
    _emailCtrl.dispose();
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
    final text = Theme.of(context).textTheme;
    // Theme defaults throughout: ink actions, Control Edge outlines, the
    // 2px ink focus ring. The old greys failed the 3:1 edge contrast.
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: AppColors.primaryContainer,
                          child: Text(user.initials,
                              style: text.headlineMedium?.copyWith(color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),

                      if (_error != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.dangerContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      const AppSectionHeader('Personal details'),
                      const SizedBox(height: AppSpacing.md),
                      _buildTextField('First name', _firstNameCtrl, Icons.person_outline),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Last name', _lastNameCtrl, Icons.person_outline),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Phone number', _phoneCtrl, Icons.phone_outlined, keyboard: TextInputType.phone),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Email', _emailCtrl, Icons.email_outlined,
                          enabled: false, required: false, helper: 'Your sign-in email cannot be changed here.'),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Home address', _addressCtrl, Icons.home_work_outlined, required: false),

                      const SizedBox(height: AppSpacing.xxxl),
                      const AppSectionHeader('Emergency contact'),
                      const SizedBox(height: AppSpacing.md),
                      _buildTextField('Contact name', _emerNameCtrl, Icons.health_and_safety_outlined, required: false),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Relation', _emerRelationCtrl, Icons.people_outline, required: false),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTextField('Contact phone', _emerPhoneCtrl, Icons.phone_outlined,
                          required: false, keyboard: TextInputType.phone),

                      const SizedBox(height: AppSpacing.xxl),
                      // One control: the label is the switch's name for a screen reader.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Change password', style: text.titleMedium),
                        value: _changingPassword,
                        onChanged: (val) => setState(() => _changingPassword = val),
                      ),
                      if (_changingPassword) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildTextField('Current password', _currentPasswordCtrl, Icons.lock_outline, obscure: true),
                        const SizedBox(height: AppSpacing.lg),
                        _buildTextField('New password', _newPasswordCtrl, Icons.lock_reset,
                            obscure: true, helper: 'At least 8 characters.'),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                border: Border(top: BorderSide(color: AppColors.edge)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AppSizing.primaryActionHeight,
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: AppSizing.primaryActionHeight,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surfaceRaised),
                              )
                            : const Text('Save changes'),
                      ),
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
    String? helper,
    TextInputType? keyboard,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icon, size: 20),
      ),
      validator: (val) {
        if (!required) return null;
        if (val == null || val.trim().isEmpty) return 'Enter your ${label.toLowerCase()}.';
        if (obscure && val.length < 8) return 'Use at least 8 characters.';
        return null;
      },
    );
  }
}
