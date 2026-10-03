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
/// white the logo's own ink and red do the branding, the actions take the
/// theme's ink fill at 18:1, and the screen matches every screen after it,
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
      backgroundColor: AppColors.surfaceRaised,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.xxxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight -
                  AppSpacing.xxxl * 2),
              // IntrinsicHeight, or the Spacers below have nothing to
              // divide: minHeight sets a floor but a scroll view's maximum
              // height is still infinite, and a flex child cannot expand to
              // fill an unbounded axis. This is what makes "scrolls when
              // cramped, spreads when roomy" legal in one layout.
              child: IntrinsicHeight(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),

                  // The mark is the title, so it is centred on its own and
                  // announced as "SabayGo" (see BrandLogo).
                  const Center(child: BrandLogo()),
                  const SizedBox(height: AppSpacing.xxl),

                  // One sentence of value, centred under the mark. Muted
                  // rather than ink so it reads as a caption to the logo,
                  // not a second headline competing with it.
                  Text(
                    'Book a space on your UV Express\nbefore you get to the terminal.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge!.copyWith(
                      color: AppColors.textMuted,
                      height: 1.55,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Theme defaults on purpose: ink fill for the one primary
                  // action, outline for the alternative. A new passenger
                  // has exactly one obvious next step (Hick's law).
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SignupScreen()),
                    ),
                    child: const Text('Create an account'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
