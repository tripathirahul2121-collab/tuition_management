import 'package:flutter/material.dart';

import '../config/app_branding.dart';

class BrandedLogo extends StatelessWidget {
  const BrandedLogo({required this.branding, required this.size, super.key});

  final AppBranding branding;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${branding.instituteName} logo',
      image: true,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: branding.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          branding.logoAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            Icons.school_rounded,
            color: branding.primaryColor,
            size: size * 0.56,
          ),
        ),
      ),
    );
  }
}
