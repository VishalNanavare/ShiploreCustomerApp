import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatx.dart';
import '../data/models/cart_item.dart';
import '../data/models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import 'network_image.dart';
import 'qty_stepper.dart';

/// Blinkit-style product tile: shadowed card, rounded image, off-badge, title,
/// price, and an animated ADD ↔ quantity stepper. Watches only its own variant's
/// quantity (via context.select) so adding to cart rebuilds just this card.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  void _add(BuildContext context) {
    if (product.hasVariants) {
      context.push('/product/${product.slug}');
      return;
    }
    context.read<CartProvider>().add(
      CartItem(
        variantId: product.defaultVariantId ?? product.id,
        productId: product.id,
        title: product.title,
        slug: product.slug,
        unitPrice: product.basePrice,
        mrp: product.mrp,
        imageUrl: product.imageUrl,
        vendorId: product.vendorId,
        vendorName: product.vendor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vid = product.defaultVariantId;
    final qty = vid == null
        ? 0
        : context.select<CartProvider, int>((c) => c.qtyFor(vid));

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: InkWell(
        onTap: () => context.push('/product/${product.slug}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Image + badges ───────────────────────────────────────────
              Stack(
                children: [
                  SizedBox(
                    height: 130,
                    width: double.infinity,
                    child: Hero(
                      tag: 'product-${product.slug}',
                      child: AppImage(url: product.imageUrl, radius: 12),
                    ),
                  ),
                  if (product.offPercent > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        child: Text(
                          '${product.offPercent}% OFF',
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: qty > 0
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: AppColors.cta,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$qty',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, height: 1.0),
                            ),
                          )
                        : WishlistHeart(product: product),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // ── Title — single line, Flutter trims at widget boundary ─────
              Text(
                product.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 4),

              // ── Price + strikethrough MRP on one row ─────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    Formatx.money(product.basePrice),
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                  if (product.onOffer) ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        Formatx.money(product.mrp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11,
                          height: 1.2,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 6),

              // ── Full-width ADD / qty stepper ──────────────────────────────
              SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: qty > 0
                      ? QtyStepper(
                          key: const ValueKey('stepper'),
                          qty: qty,
                          fillWidth: true,
                          onInc: () {
                            context.read<CartProvider>().increment(vid!).then((capped) {
                              if (capped && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Maximum 20 per item')),
                                );
                              }
                            });
                          },
                          onDec: () =>
                              context.read<CartProvider>().decrement(vid!),
                        )
                      : GestureDetector(
                          key: const ValueKey('add'),
                          onTap: () => _add(context),
                          child: Container(
                            height: 32,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.cta,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: product.hasVariants
                                ? const Text(
                                    'Options',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, height: 1.0),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_rounded, color: Colors.white, size: 14),
                                      SizedBox(width: 3),
                                      Text('ADD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, height: 1.0)),
                                    ],
                                  ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small wishlist heart for the top-right of a product card / detail. Toggles
/// the account-synced wishlist; for multi-variant products (no single variant)
/// it opens the detail so the customer can pick which option to save.
class WishlistHeart extends StatelessWidget {
  const WishlistHeart({super.key, required this.product, this.size = 17});
  final Product product;
  final double size;

  Future<void> _tap(BuildContext context) async {
    final vid = product.defaultVariantId;
    if (vid == null || product.hasVariants) {
      context.push('/product/${product.slug}');
      return;
    }
    if (!context.read<AuthProvider>().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in to save items to your wishlist')),
      );
      context.push('/login');
      return;
    }
    try {
      await context.read<WishlistProvider>().toggle(vid);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update your wishlist")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vid = product.defaultVariantId;
    final fav =
        vid != null &&
        context.select<WishlistProvider, bool>((w) => w.contains(vid));
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _tap(context),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
            child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(fav),
              size: size,
              color: fav ? AppColors.danger : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
