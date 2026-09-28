import 'package:flutter/material.dart';

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
/// The layout scrolls. The old one mixed fixed `SizedBox` heights with a
/// `Spacer` inside a non-scrolling `Column`, which overflows on a short
/// handset and again at the 200% text scale WCAG 1.4.4 requires.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.primary,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),

                  // Decorative: the wordmark below carries the meaning, so
                  // this is hidden from screen readers rather than read out
                  // as "transit icon".
                  ExcludeSemantics(
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius:
                            BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.directions_bus_filled_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Tracking is negative, not positive. Large type set
                  // loosely looks amateur; display sizes want to close up.
                  Text(
                    'SabayGo',
                    style: text.headlineLarge!.copyWith(
                      fontSize: 40,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Book a space on your UV Express\nbefore you get to the terminal.',
                    style: text.bodyLarge!.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.55,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // White on purple is 14.36:1. The old green button was
                  // white on #00A859 at 3.11:1 -- the least readable element
                  // on the screen was its primary action.
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SignupScreen()),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45)),
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
    );
  }
}
