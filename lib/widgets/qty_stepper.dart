import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Compact +/- stepper used on product cards and the cart. The quantity pops
/// with a quick scale when it changes, for tactile add-to-cart feedback.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.qty,
    required this.onInc,
    required this.onDec,
    this.dense = true,
    this.fillWidth = false,
  });

  final int qty;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final bool dense;
  // When true, the stepper expands to fill its parent's horizontal constraint.
  // Use inside a SizedBox to prevent squeezing adjacent widgets.
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final h = dense ? 30.0 : 42.0;
    return Container(
      height: h,
      width: fillWidth ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: AppGradients.cta,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: AppColors.cta.withValues(alpha: 0.30), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: fillWidth ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          _btn(Icons.remove_rounded, onDec),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Container(
              key: ValueKey(qty),
              constraints: BoxConstraints(minWidth: dense ? 20 : 24),
              alignment: Alignment.center,
              child: Text('$qty', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: dense ? 13 : 16, height: 1.0)),
            ),
          ),
          _btn(Icons.add_rounded, onInc),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 12),
          child: Icon(icon, color: Colors.white, size: dense ? 16 : 22),
        ),
      );
}
