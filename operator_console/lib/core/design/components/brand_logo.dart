import 'package:flutter/material.dart';

import '../tokens.dart';

/// The SabayGo logo (10 Nov): a light-green van carrying passengers in the
/// camera's detection boxes, with the GPS signal at its windscreen, over
/// the "SabayGo" wordmark -- the system's two witnesses, the door camera
/// and the GPS, in one picture. Announced as "SabayGo"; drawn on light
/// surfaces, its background cut away so it sits on white or the page.
///
/// [mark] draws the van alone, for the folded sidebar and the browser's
/// icons: the wordmark is unreadable at those sizes. The swoosh runs
/// through the wordmark, so the full logo is never split into a
/// side-by-side lockup.
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.height = 64, this.width, this.mark = false, super.key});

  final double height;
  final double? width;
  final bool mark;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SabayGo',
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            // New names on 10 Nov: browsers had the owl cached under the old one.
            mark ? 'assets/branding/sabaygo_van_mark.png' : 'assets/branding/sabaygo_van_logo.png',
            height: height,
            width: width,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
}

/// The logo on its own light tile, for a surface that is not white.
class BrandPlate extends StatelessWidget {
  const BrandPlate({this.height = 44, super.key});

  /// Height of the logo inside the plate.
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: height * 0.25, vertical: height * 0.14),
        decoration: BoxDecoration(
          color: AppColors.logoPlate,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: BrandLogo(height: height),
      );
}
