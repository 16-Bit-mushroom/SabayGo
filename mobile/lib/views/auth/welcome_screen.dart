import 'package:flutter/material.dart';

import '../../core/design/components/brand_logo.dart';
import '../../core/design/tokens.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// First screen a passenger ever sees.
///
/// Deliberately plain. The previous version layered a purple gradient, a
/// translucent circle and a green glow (a 50px blur at 10px spread) behind
/// the mark. Gradients and glows age badly and read as decoration applied to
/// a screen rather than a screen that was designed; a single flat brand
/// field, generous space and one clear action look more considered and cost
/// nothing to render.
///
/// Light, with the official mark as the hero (3 Oct). The flat
/// purple field it replaced pushed every element to white-on-colour; on
/// white the logo does the branding, the actions take the theme's emerald
/// fill with dark text (6.03:1; the console's palette since 10 Nov), and
/// the screen matches every screen after it,
/// so the first impression is the app rather than a splash for it (Jakob's
/// law: one look, end to end). The CTA is at the bottom, in thumb reach.
///
/// The layout scrolls. The old one mixed fixed `SizedBox` heights with a
/// `Spacer` inside a non-scrolling `Column`, which overflows on a short
/// handset and again at the 200% text scale WCAG 1.4.4 requires.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.xxl * 2),
              // IntrinsicHeight, or the Spacers below have nothing to
              // divide: minHeight sets a floor but a scroll view's maximum
              // height is still infinite, and a flex child cannot expand to
              // fill an unbounded axis. This is what makes "scrolls when
              // cramped, spreads when roomy" legal in one layout.
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    // The mark is the title, so it is centred on its own
                    // card and announced as "SabayGo" (see BrandLogo).
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: AppColors.edge),
                        ),
                        child: const BrandLogo(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'A2Z Transport Cooperative · Davao City',
                      textAlign: TextAlign.center,
                      style: text.labelLarge!.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Book a seat on your UV Express before you get to the terminal.',
                      textAlign: TextAlign.center,
                      style: text.titleLarge!.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // How it works, once, before anyone signs up: the cash
                    // rule is the one thing a new passenger does not expect
                    // (20 Nov redesign, after Gemini's study).
                    const _HowItWorks(),
                    const Spacer(),
                    const SizedBox(height: AppSpacing.xl),
                    // Theme defaults on purpose: the filled button for the
                    // one primary action, outline for the alternative. A new
                    // passenger has exactly one obvious next step (Hick).
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      ),
                      child: const Text('Create an account'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reserve, pay in cash, board: three steps side by side, or one under
/// another when the text is large or the phone narrow. Decided from the
/// text scale, not a LayoutBuilder, because the screen measures its column
/// with IntrinsicHeight, which a LayoutBuilder cannot answer.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    ('Reserve a seat', 'Get a booking code'),
    ('Pay in cash', 'To the Dispatcher at the terminal'),
    ('Board the van', 'At the starting terminal'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final roomy = MediaQuery.textScalerOf(context).scale(1) <= 1.3 && MediaQuery.sizeOf(context).width >= 340;

    Widget number(int n) => Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
          child: Text('$n', style: text.labelLarge!.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
        );
    Widget words(String title, String note, {required bool centred}) => Column(
          crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(title,
                textAlign: centred ? TextAlign.center : TextAlign.start,
                style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
            Text(note, textAlign: centred ? TextAlign.center : TextAlign.start, style: text.bodySmall),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('HOW IT WORKS · CASH ONLY',
                style: text.labelSmall!.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (roomy)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, (title, note)) in _steps.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(children: [
                      number(i + 1),
                      const SizedBox(height: AppSpacing.sm),
                      words(title, note, centred: true),
                    ]),
                  ),
                ],
              ],
            )
          else
            for (final (i, (title, note)) in _steps.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                number(i + 1),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: words(title, note, centred: false)),
              ]),
            ],
        ],
      ),
    );
  }
}
