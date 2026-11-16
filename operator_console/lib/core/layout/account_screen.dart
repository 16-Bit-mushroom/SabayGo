import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_provider.dart';
import '../design/components/page_header.dart';
import '../design/components/panel.dart';
import '../design/components/password_field.dart';
import '../design/components/status_badge.dart';
import '../design/tokens.dart';
import '../network/api_exception.dart';

/// The signed-in office user's own account, as a page of its own
/// (`#/account`, from "My account" under the name in the top bar).
///
/// It was a dialog until 10 Nov; a page reads as part of the console, has
/// room for the two jobs side by side, and keeps its address on refresh.
/// Details and password are separate panels with their own button, so
/// changing a phone number never asks for a password and a password
/// change never resaves the name. Email and role are shown, not edited:
/// the email is the sign-in identity, and a role is granted by the
/// administrator, never chosen by its holder.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'My account',
                description: 'Your name, mobile number and password. Your email and role are set by the '
                    'administrator.',
              ),
              LayoutBuilder(builder: (context, c) {
                const details = _DetailsPanel();
                const password = _PasswordPanel();
                if (c.maxWidth < 860) {
                  return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    details,
                    SizedBox(height: AppSpacing.lg),
                    password,
                  ]);
                }
                return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: details),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: password),
                ]);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatefulWidget {
  const _DetailsPanel();

  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
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
    for (final c in [_first, _last, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

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
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details saved.')));
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
    final name = p?.displayName ?? p?.email ?? '';
    return Panel(
      title: 'Your details',
      icon: Icons.badge_outlined,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Who this desk is signed in as, before anything to change.
            Row(children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                      style: text.titleLarge?.copyWith(color: AppColors.onFill)),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  if (p != null) StatusBadge(p.role.title, tone: Tone.info),
                ]),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            _Fact('Email', p?.email ?? ''),
            _Fact('Role', p?.role.title ?? ''),
            const Divider(height: AppSpacing.xxl),
            Row(children: [
              Expanded(child: _field(_first, 'First name')),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _field(_last, 'Last name')),
            ]),
            const SizedBox(height: AppSpacing.md),
            _field(_phone, 'Mobile number', helper: '09XXXXXXXXX or +639XXXXXXXXX', phone: true),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Save details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? helper, bool phone = false}) => TextFormField(
        controller: c,
        keyboardType: phone ? TextInputType.phone : null,
        decoration: InputDecoration(labelText: label, helperText: helper),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your ${label.toLowerCase()}.' : null,
      );
}

class _PasswordPanel extends StatefulWidget {
  const _PasswordPanel();

  @override
  State<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends State<_PasswordPanel> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _change() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().updateProfile(currentPassword: _current.text, newPassword: _new.text);
      if (!mounted) return;
      for (final c in [_current, _new, _confirm]) {
        c.clear();
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
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
    final text = Theme.of(context).textTheme;
    return Panel(
      title: 'Password',
      icon: Icons.lock_outline,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Use at least 8 characters. Do not reuse the password of a shared PC.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: AppSpacing.lg),
            PasswordField(
              controller: _current,
              label: 'Current password',
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password.' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _new,
              label: 'New password',
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters.' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              validator: (v) => v != _new.text ? 'This does not match the new password.' : null,
              onSubmitted: (_) => _change(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              // Outlined: one filled button per view, and saving details is it.
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _change,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.key_outlined, size: 18),
                label: const Text('Change password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fact row: a muted label beside its value (DESIGN.md, 132 px label).
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(children: [
        SizedBox(width: 132, child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
        Expanded(child: Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
