import 'package:flutter/material.dart';

import '../tokens.dart';

/// The official SABAY GO mark. Same asset and contract as the mobile app's
/// `BrandLogo`: announced as "SabayGo", drawn only on light surfaces. The
/// console is dark, so it shows the mark inside a [BrandPlate].
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.height = 64, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SabayGo',
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            'assets/branding/sabaygo_logo.png',
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
}

/// The mark on its own light tile -- the ink owl would vanish on the dark
/// console, and recolouring a logo is not ours to do.
class BrandPlate extends StatelessWidget {
  const BrandPlate({this.height = 44, super.key});

  /// Height of the mark inside the plate.
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: height * 0.25, vertical: height * 0.14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: BrandLogo(height: height),
      );
}
