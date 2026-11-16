import 'package:flutter/material.dart';

import '../tokens.dart';

/// A password field with a show/hide button, so the person typing a
/// temporary password for someone else can check it before saving.
/// Every password field in the console uses this one.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.prefixIcon,
    this.validator,
    this.onSubmitted,
    this.labelAbove = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  /// The form shows the label as a heading above the field (sign-in), so
  /// inside it the label is only the placeholder.
  final bool labelAbove;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: widget.labelAbove ? null : widget.label,
        hintText: widget.labelAbove ? widget.label : null,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(
            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.textMuted,
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
