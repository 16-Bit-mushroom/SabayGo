import 'package:flutter/material.dart';

/// The official SABAY GO mark.
///
/// One widget so the asset path, the size steps and the screen-reader name
/// have a single owner. The image is the wordmark itself, so it is announced
/// as "SabayGo" rather than hidden: on the welcome screen it *is* the title.
///
/// The PNG is transparent and drawn in ink and red, so it is legible only on
/// a light surface. That is a constraint, not an oversight -- the passenger
/// app is light-first, and there is no dark variant of the mark to fall back
/// to.
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.height = BrandLogoSize.hero, super.key});

  /// Height in logical pixels. The width follows the mark's ~2:1 aspect.
  final double height;

  static const _asset = 'assets/branding/sabaygo_logo.png';

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SabayGo',
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            _asset,
            height: height,
            fit: BoxFit.contain,
            // Upscaling a raster mark blurs it; filterQuality keeps the owl's
            // edges clean at the app-bar size, where it is downscaled most.
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
}

/// The three sizes the mark appears at. Fixed steps, so two screens never
/// show it at almost-but-not-quite the same size.
class BrandLogoSize {
  /// Welcome and splash: the first thing a new passenger sees.
  static const double hero = 120;

  /// Above a form heading (sign in, sign up).
  static const double header = 72;

  /// Inside the app bar on the Home tab.
  static const double bar = 36;
}
