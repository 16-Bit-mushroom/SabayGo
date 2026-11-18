import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../viewmodels/auth_provider.dart';
import '../../../core/design/components/brand_logo.dart';
import '../../../core/design/components/password_field.dart';
import '../../../core/design/tokens.dart';

/// The office console's door (10 Nov, the owner's split design): on the
/// left what the console is for, on a deep green panel; on the right the
/// sign-in form.
///
/// Kept honest where the mock-up was not: the van card on the left is
/// labelled an example (nothing is live before sign-in, and a van holds
/// 14, not 15); there is no "Secure SSL" or "Auth Guard" (the console runs
/// over plain HTTP on the office network); no role is shown before anyone
/// signs in; and the 12-hour session is said, not offered as a switch,
/// because it is not one. Forgotten passwords go to the Terminal Manager,
/// who made the account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.login(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  void _help(String title) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: const Text(
            'Office accounts are made by A2Z\'s Terminal Manager in Setup → Staff. Ask them to set a new '
            'temporary password for you, or to check that your account is working.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(children: [
        // Two soft blooms of the palette behind the card. Decoration only.
        const Positioned(left: -160, top: -120, child: _Bloom(size: 520)),
        const Positioned(right: -180, bottom: -160, child: _Bloom(size: 560)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: LayoutBuilder(builder: (context, c) {
              final split = c.maxWidth >= 900;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: split ? 1020 : 460),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.edge),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 18)),
                    ],
                  ),
                  child: split
                      ? IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            const Expanded(flex: 10, child: _BrandPanel()),
                            Expanded(flex: 14, child: _form(context)),
                          ]),
                        )
                      : _form(context),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  Widget _form(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final text = Theme.of(context).textTheme;
    final label = text.labelMedium?.copyWith(letterSpacing: 0.8, color: AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandLogo(height: 96)),
            const SizedBox(height: AppSpacing.sm),
            Text('A2Z office console. Sign in with your office account.',
                textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: AppSpacing.xxl),
            if (auth.error != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.dangerContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.danger),
                  ),
                  child: Text(auth.error!, style: TextStyle(color: AppColors.danger)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('OFFICE EMAIL', style: label),
            const SizedBox(height: AppSpacing.xs + 2),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'Your office email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your office email.' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              Expanded(child: Text('PASSWORD', style: label)),
              TextButton(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.padded),
                onPressed: () => _help('Forgot your password?'),
                child: const Text('Forgot password?'),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            PasswordField(
              controller: _passwordController,
              label: 'Your password',
              labelAbove: true,
              prefixIcon: Icons.lock_outline,
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password.' : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              const Icon(Icons.schedule, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Stays signed in on this PC for up to 12 hours',
                    style: text.bodySmall?.copyWith(color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.edge),
                ),
                child: Text('Office staff only',
                    style: text.labelSmall?.copyWith(color: AppColors.primary, letterSpacing: 0)),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: auth.isBusy ? null : _submit,
                child: auth.isBusy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                      )
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Sign in to Office Console', style: TextStyle(fontSize: 15)),
                        SizedBox(width: AppSpacing.sm),
                        Icon(Icons.arrow_forward, size: 18),
                      ]),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: Text('Accounts are made by the Terminal Manager',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: () => _help('Need help signing in?'),
                child: const Text('Need help?'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The left half: what the console is for, on deep green (white on it
/// 5.48:1 and better), with a van as it appears inside -- marked an example.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _deep = Color(0xFF065F46);
  static const _muted = Color(0xE6FFFFFF); // white at 90 %: still above 4.5:1 on the green

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, _deep],
        ),
      ),
      child: Stack(children: [
        // A route line drawn across the panel, the brief's road. Decoration.
        const Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7,
                    decoration: const BoxDecoration(color: Color(0xFF86EFAC), shape: BoxShape.circle)),
                const SizedBox(width: AppSpacing.sm),
                Text('A2Z Cooperative Office',
                    style: text.labelMedium?.copyWith(color: Colors.white, letterSpacing: 0.2)),
              ]),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('Smart Van Fleet &\nBoarding Oversight.',
                style: const TextStyle(
                    fontFamily: 'PlusJakartaSans', fontSize: 32, height: 1.15, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: -0.6)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'YOLOv8 door camera passenger counts, GPS trip tracking and terminal fee reconciliation in '
              'one console.',
              style: text.bodyLarge?.copyWith(color: _muted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            const _ExampleVan(),
            const Spacer(),
            Divider(color: Colors.white.withValues(alpha: 0.22)),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: Text('A2Z Transport Cooperative, Davao City',
                    style: text.bodySmall?.copyWith(color: _muted)),
              ),
              const SizedBox(width: AppSpacing.md),
              Text('Office console', style: text.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// A van as the console shows one: plate, route, the door camera's count
/// against its 14 spaces, the GPS. Labelled an example in words, since
/// nothing here is read from a van.
class _ExampleVan extends StatelessWidget {
  const _ExampleVan();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget tile(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: text.labelSmall?.copyWith(color: const Color(0xE6FFFFFF), letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontFamily: 'PlusJakartaSans', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        );
    return Semantics(
      label: 'Example of a van on the console: TST-1023, Ecoland to Cotabato, 12 of 14 aboard by the door '
          'camera, GPS every 15 seconds.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(Icons.airport_shuttle_outlined, size: 18, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text('TST-1023',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12,
                            letterSpacing: 0.6)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('Ecoland – Cotabato, near Digos',
                    style: text.bodySmall?.copyWith(color: const Color(0xE6FFFFFF))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF86EFAC),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text('Example',
                  style: text.labelSmall?.copyWith(color: AppColors.textPrimary, letterSpacing: 0)),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              tile('YOLOV8 DOOR COUNT', '12 of 14 aboard'),
              const SizedBox(width: AppSpacing.sm),
              tile('GPS UPDATES', 'Every 15 s'),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.18);
    final path = Path()
      ..moveTo(-20, size.height * 0.30)
      ..cubicTo(size.width * 0.35, size.height * 0.12, size.width * 0.55, size.height * 0.62, size.width + 20,
          size.height * 0.40);
    // Dashes along the curve.
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), dash);
      }
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.92), size.width * 0.35, arc);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => false;
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppColors.accent.withValues(alpha: 0.10),
              AppColors.accent.withValues(alpha: 0),
            ]),
          ),
        ),
      );
}
