import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../viewmodels/auth_provider.dart';
import 'signup_screen.dart';

/// Sign-in, wired to POST /auth/login.
///
/// Replaces the previous screen, which routed by email prefix — an
/// "admin@" address opened the crew portal. The server now decides the
/// role and the app follows it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final ok = await context.read<AuthProvider>().login(
          email: _email.text,
          password: _password.text,
        );

    // The root router already swapped to the right shell, but this
    // screen was pushed on top of it and would keep covering it. Clear
    // the stack back to the router rather than pushing another route,
    // so there is no back gesture returning to a stale sign-in form.
    if (ok && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign in to book a seat or start your shift.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 28),

                if (auth.error != null) ...[
                  _ErrorBanner(
                    message: auth.error!,
                    onDismiss: auth.clearError,
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter your email';
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 28),

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
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: auth.isBusy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const SignupScreen(),
                          ),
                        ),
                  child: const Text("Don't have an account? Create one"),
                ),

                if (AppConfig.isDebug) ...[
                  const SizedBox(height: 32),
                  _DebugPanel(
                    onPick: (email) {
                      _email.text = email;
                      _password.text = 'sabaygo123';
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
          // The backend writes messages for people to read, so they are
          // shown verbatim rather than swapped for a generic string.
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

/// Debug-only account shortcuts. Compiled out of release builds by the
/// AppConfig.isDebug guard, so seeded credentials cannot ship.
class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.onPick});

  final void Function(String email) onPick;

  static const _accounts = <String, String>{
    'Passenger': 'passenger@sabaygo.dev',
    'Conductor': 'conductor@sabaygo.dev',
    'Driver': 'driver@sabaygo.dev',
    'Coop admin': 'coopadmin@sabaygo.dev',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bug_report_outlined,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              'Dev accounts — ${AppConfig.apiBaseUrl}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _accounts.entries)
              ActionChip(
                label: Text(entry.key, style: const TextStyle(fontSize: 12)),
                onPressed: () => onPick(entry.value),
              ),
          ],
        ),
      ],
    );
  }
}
