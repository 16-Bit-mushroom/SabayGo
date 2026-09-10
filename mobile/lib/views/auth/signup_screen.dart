import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../viewmodels/auth_provider.dart';

/// Passenger self-registration, wired to POST /auth/register.
///
/// Two things changed from the previous version.
///
/// The "I'm a van terminal" checkbox is gone. It routed to the crew
/// portal, so anyone registering could tick it and land in the conductor
/// app. The backend never honoured it -- /auth/register creates
/// passengers only -- but a control that implies otherwise is worth
/// removing rather than leaving to be refused server-side. Conductors,
/// drivers and cooperative administrators are provisioned by the office,
/// because employment is a cooperative decision, not self-service.
///
/// There is also no navigation on success. The root router watches the
/// auth state and moves the app itself, so a screen that pushed its own
/// route would fight it.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms to continue.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    await context.read<AuthProvider>().register(
          email: _email.text,
          phoneNumber: _phone.text,
          password: _password.text,
          firstName: _firstName.text,
          lastName: _lastName.text,
        );
    // Same as sign-in: the router has already switched, so clear this
    // screen off the stack instead of pushing anything.
    if (mounted && context.read<AuthProvider>().status == AuthStatus.signedIn) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          Container(
            height: 280,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, Color(0xFF4A3592)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          const Center(
                            child: Text(
                              'Create Your Account',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Book a seat on your UV Express route.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 20,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (auth.error != null) ...[
                                  _ErrorBanner(
                                    message: auth.error!,
                                    onDismiss: auth.clearError,
                                  ),
                                  const SizedBox(height: 18),
                                ],

                                Row(
                                  children: [
                                    Expanded(
                                      child: _Field(
                                        label: 'First name*',
                                        controller: _firstName,
                                        hint: 'Juan',
                                        icon: Icons.person_outline,
                                        validator: _required('first name'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _Field(
                                        label: 'Last name*',
                                        controller: _lastName,
                                        hint: 'Dela Cruz',
                                        validator: _required('last name'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                _Field(
                                  label: 'Email address*',
                                  controller: _email,
                                  hint: 'you@example.com',
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    final s = v?.trim() ?? '';
                                    if (s.isEmpty) return 'Enter your email';
                                    if (!s.contains('@') || !s.contains('.')) {
                                      return 'Enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 18),

                                _Field(
                                  label: 'Mobile number*',
                                  controller: _phone,
                                  hint: '09171234567',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                  // Mirrors the server's PhoneNumber rule so
                                  // an obvious typo is caught before a round
                                  // trip. The server still validates.
                                  validator: (v) {
                                    final s = (v ?? '').replaceAll(' ', '');
                                    if (s.isEmpty) return 'Enter your number';
                                    final local =
                                        s.startsWith('09') && s.length == 11;
                                    final intl =
                                        s.startsWith('+639') && s.length == 13;
                                    if (!local && !intl) {
                                      return 'Use 09XXXXXXXXX or +639XXXXXXXXX';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 18),

                                _Field(
                                  label: 'Password*',
                                  controller: _password,
                                  hint: 'At least 8 characters',
                                  icon: Icons.lock_outline,
                                  obscure: _obscure,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Choose a password';
                                    }
                                    if (v.length < 8) {
                                      return 'At least 8 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),

                                CheckboxListTile(
                                  value: _agreedToTerms,
                                  onChanged: (v) =>
                                      setState(() => _agreedToTerms = v ?? false),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  activeColor: AppColors.accent,
                                  title: const Text(
                                    'I agree to the terms of use and privacy notice.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                FilledButton(
                                  onPressed: auth.isBusy ? null : _submit,
                                  child: auth.isBusy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Create account'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          Center(
                            child: TextButton(
                              onPressed: auth.isBusy
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Already have an account? Sign in'),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? Function(String?) _required(String what) =>
      (v) => (v == null || v.trim().isEmpty) ? 'Enter your $what' : null;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          // Server messages name the field that clashed -- "That phone
          // number is already registered" -- so they are shown as written.
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, height: 1.35),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.danger,
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}