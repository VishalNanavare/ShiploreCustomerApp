import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/cart_provider.dart';

/// Sticky floating "View cart" pill (Swiggy-style), hidden when empty.
/// Slides up when the first item lands. Switches to Cart tab via go().
class CartBar extends StatelessWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (cart.isEmpty) return const SizedBox.shrink();

    final itemLabel = '${cart.count} Item${cart.count == 1 ? '' : 's'}';
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: 70 + bottom,
      child: Padding(
        padding: EdgeInsets.only(bottom: 14 + bottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: Material(
                color: AppColors.cta,
                borderRadius: BorderRadius.circular(50),
                elevation: 10,
                shadowColor: AppColors.cta.withValues(alpha: 0.45),
                child: InkWell(
                  borderRadius: BorderRadius.circular(50),
                  onTap: () => context.go('/cart'),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        // Cart icon badge
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shopping_bag_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Labels
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'View cart',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                itemLabel,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.80),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Chevron
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 260.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms);
  }
}
