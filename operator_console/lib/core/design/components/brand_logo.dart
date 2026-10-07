import 'package:flutter/material.dart';

/// The official SABAY GO mark. Same asset and contract as the mobile app's
/// `BrandLogo`: announced as "SabayGo", drawn only on light surfaces.
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
