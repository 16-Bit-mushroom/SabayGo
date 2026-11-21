import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/app_card.dart';
import '../../core/design/tokens.dart';
import '../../viewmodels/auth_provider.dart';

/// Passenger self-registration, wired to POST /auth/register.
///
/// Two things changed from the previous version.
///
/// The "I'm a van terminal" checkbox is gone. It routed to the crew
/// portal, so anyone registering could tick it and land in the Dispatcher
/// app. The backend never honoured it -- /auth/register creates
/// passengers only -- but a control that implies otherwise is worth
/// removing rather than leaving to be refused server-side. Dispatchers,
/// Cashiers and the Terminal Manager are provisioned by the office,
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

    // First and last name side by side, or stacked at large text.
    final roomy = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    final first = _Field(
      label: 'First name*',
      controller: _firstName,
      hint: 'Juan',
      icon: Icons.person_outline,
      validator: _required('first name'),
    );
    final last = _Field(
      label: 'Last name*',
      controller: _lastName,
      hint: 'Dela Cruz',
      validator: _required('last name'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create your account', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  'Book a seat on your UV Express route.',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Said before the form, not after a refused attempt: staff
                // accounts are the office's to make (20 Nov redesign).
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.edge),
                  ),
                  child: const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Passenger accounts only. ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: 'Dispatcher and office accounts are made by the A2Z office.'),
                    ]),
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (auth.error != null) ...[
                  _ErrorBanner(message: auth.error!, onDismiss: auth.clearError),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (roomy)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: first),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: last),
                        ])
                      else ...[
                        first,
                        const SizedBox(height: 18),
                        last,
                      ],
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
                        helper: 'Use 09XXXXXXXXX or +639XXXXXXXXX',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        // Mirrors the server's PhoneNumber rule so an obvious
                        // typo is caught before a round trip. The server
                        // still validates.
                        validator: (v) {
                          final s = (v ?? '').replaceAll(' ', '');
                          if (s.isEmpty) return 'Enter your number';
                          final local = s.startsWith('09') && s.length == 11;
                          final intl = s.startsWith('+639') && s.length == 13;
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
                        hint: 'Choose a password',
                        helper: 'At least 8 characters',
                        icon: Icons.lock_outline,
                        obscure: _obscure,
                        suffix: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Choose a password';
                          if (v.length < 8) return 'At least 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: _agreedToTerms,
                        onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.primary,
                        title: const Text(
                          'I agree to the terms of use and privacy notice.',
                          style: TextStyle(fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: auth.isBusy ? null : _submit,
                        child: auth.isBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                              )
                            : const Text('Create account'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: auth.isBusy ? null : () => Navigator.pop(context),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    this.helper,
    this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  /// A line under the field that says the format before anything is typed.
  final String? helper;
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
            helperText: helper,
            helperMaxLines: 2,
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
        color: AppColors.dangerContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger),
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
            tooltip: 'Dismiss',
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