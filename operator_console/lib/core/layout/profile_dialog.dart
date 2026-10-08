import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_provider.dart';
import '../design/tokens.dart';
import '../network/api_exception.dart';

/// The signed-in office user's own account: name, phone, password.
///
/// Opened from the user row at the foot of the sidebar -- the place a
/// person already looks for "me". Email and role are shown but not
/// editable: the email is the sign-in identity, and a role is granted by
/// the administrator, never chosen by its holder.
class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = context.read<AuthProvider>().profile;
    _first = TextEditingController(text: p?.firstName ?? '');
    _last = TextEditingController(text: p?.lastName ?? '');
    _phone = TextEditingController(text: p?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _changingPassword => _new.text.isNotEmpty || _current.text.isNotEmpty;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().updateProfile(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            phoneNumber: _phone.text.trim(),
            currentPassword: _changingPassword ? _current.text : null,
            newPassword: _changingPassword ? _new.text : null,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(_changingPassword ? 'Profile and password saved.' : 'Profile saved.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AuthProvider>().profile;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('My profile', style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReadOnlyRow(label: 'Email', value: p?.email ?? ''),
                _ReadOnlyRow(label: 'Role', value: 'Cooperative office (${p?.role.wire ?? ''})'),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: _field(_first, 'First name', required: true)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _field(_last, 'Last name', required: true)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _field(_phone, 'Mobile number', required: true,
                    hint: '09XXXXXXXXX or +639XXXXXXXXX'),
                const SizedBox(height: AppSpacing.xxl),
                Text('Change password',
                    style: text.titleSmall!.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                Text('Leave blank to keep the current password.',
                    style: text.bodySmall!.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.md),
                _field(_current, 'Current password', obscure: true, validator: (v) {
                  if (_new.text.isNotEmpty && (v == null || v.isEmpty)) {
                    return 'Needed to set a new password';
                  }
                  return null;
                }),
                const SizedBox(height: AppSpacing.md),
                _field(_new, 'New password', obscure: true, validator: (v) {
                  if (_current.text.isNotEmpty && (v == null || v.isEmpty)) {
                    return 'Enter the new password';
                  }
                  if (v != null && v.isNotEmpty && v.length < 8) {
                    return 'At least 8 characters';
                  }
                  return null;
                }),
                const SizedBox(height: AppSpacing.md),
                _field(_confirm, 'Confirm new password', obscure: true, validator: (v) {
                  if (_new.text.isNotEmpty && v != _new.text) return 'Does not match';
                  return null;
                }),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool obscure = false,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
              : null),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: text.bodySmall!.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: text.bodyMedium!.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
