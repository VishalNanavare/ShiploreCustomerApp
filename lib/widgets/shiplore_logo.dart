import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shiplore logo from the canonical PNG asset.
/// [size] — width = height in logical pixels.
class ShiploreLogo extends StatelessWidget {
  const ShiploreLogo({super.key, this.size = 80, this.white = false});
  final double size;
  final bool white;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// The logo presented as a clean circular white "coin" with a soft drop shadow
/// and a subtle brand glow — the canonical way to show the logo on the navy
/// hero/splash backgrounds (the PNG is already a white circular badge, so we
/// clip it to a circle instead of boxing it in a clashing rounded square).
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 84});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.cta.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}
