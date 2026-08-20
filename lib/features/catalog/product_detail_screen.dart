import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/wishlist_provider.dart';
import '../../widgets/network_image.dart';
import '../../widgets/product_card.dart';
import '../../widgets/qty_stepper.dart';
import '../../widgets/states.dart';
import '../cart/cart_bar.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.slug});
  final String slug;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<ProductDetail> _future;
  final _page = PageController();
  int _image = 0;

  @override
  void initState() {
    super.initState();
    _future = context.read<CatalogRepository>().product(widget.slug);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _future = context.read<CatalogRepository>().product(widget.slug);
  });

  CartItem _toCartItem(ProductDetail d, Variant v) => CartItem(
    variantId: v.variantId,
    productId: d.product.id,
    title: d.product.title,
    slug: d.product.slug,
    unitPrice: v.basePrice,
    mrp: v.mrp,
    imageUrl: d.images.isNotEmpty ? d.images.first : d.product.imageUrl,
    variantLabel: v.label,
    vendorId: d.product.vendorId,
    vendorName: d.product.vendor,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProductDetail>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Product')),
            body: const LoadingView(),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          final isGone = err is ApiException && err.isNotFound;
          return Scaffold(
            appBar: AppBar(title: const Text('Product')),
            body: isGone
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.inkSoft.withValues(alpha: 0.5)),
                          const SizedBox(height: 20),
                          const Text(
                            'Product no longer available',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'This item has been removed or is out of stock.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkSoft, fontSize: 14, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.explore_rounded, size: 18),
                            label: const Text('Browse similar items'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ErrorView(error: snap.error!, onRetry: _reload),
          );
        }

        final d = snap.data!;
        final cart = context.watch<CartProvider>();
        final images = d.images.isNotEmpty ? d.images : [d.product.imageUrl];
        final isSimple = d.variants.length <= 1;
        final v = _primaryVariant(d);

        return Scaffold(
          appBar: AppBar(
            title: Text(d.product.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              _DetailHeartButton(variantId: v.variantId),
              const SizedBox(width: 4),
            ],
          ),
          // Sticky buy bar (simple products) + the floating cart bar sit in the
          // bottom slot — NOT as Column/Expanded siblings of the scroll view — so
          // the body can never be starved of height (the old blank-detail crash class).
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSimple)
                _StickyBuyBar(
                  variant: v,
                  cart: cart,
                  onAdd: () => cart.add(_toCartItem(d, v)),
                ),
              const CartBar(),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Carousel(
                  images: images,
                  slug: widget.slug,
                  controller: _page,
                  index: _image,
                  onChanged: (i) => setState(() => _image = i),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(detail: d, reviews: d.reviews).animate().fadeIn(duration: 240.ms),
                      const SizedBox(height: 14),
                      _PriceBlock(
                        variant: v,
                      ).animate().fadeIn(delay: 60.ms, duration: 240.ms),
                      if (d.highlights.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _ChipsRow(
                          items: d.highlights,
                        ).animate().fadeIn(delay: 100.ms, duration: 240.ms),
                      ],
                      const SizedBox(height: 16),
                      const _InfoCards().animate().fadeIn(
                        delay: 140.ms,
                        duration: 240.ms,
                      ),
                      if (!isSimple) ...[
                        const SizedBox(height: 22),
                        _VariantList(
                          detail: d,
                          cart: cart,
                          toItem: _toCartItem,
                        ),
                      ],
                      if (d.highlights.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _Section(
                          title: 'Highlights',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final h in d.highlights)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          top: 3,
                                          right: 8,
                                        ),
                                        child: Icon(
                                          Icons.check_circle,
                                          size: 15,
                                          color: AppColors.success,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          h,
                                          style: const TextStyle(height: 1.35),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 240.ms),
                      ],
                      if ((d.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _Section(
                          title: 'About this product',
                          child: Text(
                            d.description!,
                            style: const TextStyle(
                              color: AppColors.ink,
                              height: 1.5,
                            ),
                          ),
                        ).animate().fadeIn(duration: 240.ms),
                      ],
                      if (context.watch<AuthProvider>().isLoggedIn) ...[
                        const SizedBox(height: 22),
                        OutlinedButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            builder: (_) => _WriteReviewSheet(
                                productId: d.product.id),
                          ),
                          icon: const Icon(Icons.rate_review_rounded, size: 18),
                          label: const Text('Write a Review'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _ReviewsSection(reviews: d.reviews).animate().fadeIn(duration: 240.ms),
                      if (d.related.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _SimilarRail(
                          products: d.related,
                        ).animate().fadeIn(duration: 240.ms),
                      ],
                      if (d.product.vendorId != null) ...[
                        const SizedBox(height: 24),
                        _StoreRail(
                          vendorId: d.product.vendorId!,
                          vendor: d.product.vendor,
                          excludeId: d.product.id,
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Variant _primaryVariant(ProductDetail d) => d.variants.isNotEmpty
      ? d.variants.first
      : Variant(
          variantId: d.product.defaultVariantId ?? d.product.id,
          basePrice: d.product.basePrice,
          mrp: d.product.mrp,
        );
}

/// Swipeable image carousel with amber page dots.
class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.images,
    required this.slug,
    required this.controller,
    required this.index,
    required this.onChanged,
  });
  final List<String> images;
  final String slug;
  final PageController controller;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          SizedBox(
            height: 320,
            child: PageView(
              controller: controller,
              onPageChanged: onChanged,
              children: [
                for (var i = 0; i < images.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: i == 0
                        ? Hero(
                            tag: 'product-$slug',
                            child: AppImage(url: images[i], radius: 16, fit: BoxFit.contain),
                          )
                        : AppImage(url: images[i], radius: 16, fit: BoxFit.contain),
                  ),
              ],
            ),
          ),
          if (images.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == index ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == index ? AppColors.cta : AppColors.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Title, vendor and a dynamic rating pill (hidden when no reviews).
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.reviews});
  final ProductDetail detail;
  final List<ProductReview> reviews;

  @override
  Widget build(BuildContext context) {
    final vendor = detail.product.vendor ?? '';
    final hasRating = reviews.isNotEmpty;
    final avg = hasRating
        ? reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                detail.product.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  height: 1.25,
                ),
              ),
            ),
            if (hasRating) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 3),
                    Text(
                      avg.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (vendor.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'by $vendor',
            style: const TextStyle(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Big price, struck MRP and amber % OFF badge.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.variant});
  final Variant variant;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          Formatx.money(variant.basePrice),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 28,
            height: 1,
          ),
        ),
        if (variant.onOffer) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              Formatx.money(variant.mrp),
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 15,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${variant.offPercent}% OFF',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Small rounded attribute chips (bgTint) drawn from highlights.
class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final chips = items.where((s) => s.length <= 28).take(4).toList();
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgTint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              c,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }
}

/// Two shadowed assurance cards: delivery time + returns.
class _InfoCards extends StatelessWidget {
  const _InfoCards();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _InfoCard(
            icon: Icons.bolt_rounded,
            title: 'Delivery in 12 min',
            subtitle: 'Lightning fast',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _InfoCard(
            icon: Icons.cached_rounded,
            title: '7-day replacement',
            subtitle: 'Easy returns',
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.ctaTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.cta, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section wrapper with a bold header.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Customer reviews section shown on product detail.
class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews});
  final List<ProductReview> reviews;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Customer Reviews',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (reviews.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA000).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFA000)),
                    const SizedBox(width: 3),
                    Text(
                      '${(reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length).toStringAsFixed(1)} (${reviews.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFFA000)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No reviews yet — be the first to review this product!',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
            ),
          )
        else
          ...reviews.map((r) => _ReviewTile(review: r)),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16,
                    color: const Color(0xFFFFA000),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.author,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (review.createdAt != null)
                Text(
                  _formatDate(review.createdAt!),
                  style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
            ],
          ),
          if ((review.title ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(review.title!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
          if ((review.body ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(review.body!, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4)),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

/// Horizontal rail of related products using the shared ProductCard.
class _SimilarRail extends StatelessWidget {
  const _SimilarRail({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Similar products',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                SizedBox(width: 150, child: ProductCard(product: products[i])),
          ),
        ),
      ],
    );
  }
}

/// Horizontal rail of other products from the same store/vendor.
/// Loads lazily once the detail is available; renders nothing when empty.
class _StoreRail extends StatefulWidget {
  const _StoreRail({
    required this.vendorId,
    required this.vendor,
    required this.excludeId,
  });
  final int vendorId;
  final String? vendor;
  final int excludeId;

  @override
  State<_StoreRail> createState() => _StoreRailState();
}

class _StoreRailState extends State<_StoreRail> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Product>> _load() async {
    final page = await context.read<CatalogRepository>().products(
      vendorId: widget.vendorId,
    );
    if (!mounted) return const [];
    return page.items.where((p) => p.id != widget.excludeId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vendor = (widget.vendor ?? '').trim();
    final title = vendor.isNotEmpty
        ? 'More from $vendor'
        : 'More from this store';
    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snap) {
        final products = snap.data ?? const <Product>[];
        if (products.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: products.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                  width: 150,
                  child: ProductCard(product: products[i]),
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 240.ms);
      },
    );
  }
}

/// Variant picker rows (multi-variant products) with inline add/stepper.
class _VariantList extends StatelessWidget {
  const _VariantList({
    required this.detail,
    required this.cart,
    required this.toItem,
  });
  final ProductDetail detail;
  final CartProvider cart;
  final CartItem Function(ProductDetail, Variant) toItem;

  @override
  Widget build(BuildContext context) {
    // Every Column/Row here is mainAxisSize.min: this widget lives inside a
    // vertical scroll view, whose Rows pass an UNBOUNDED height down — a default
    // (max) Column would try to fill it and silently collapse the whole scroll
    // view (the variant-detail "blank page" bug). Keep them content-sized.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Select an option', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        for (final v in detail.variants)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppShadows.soft,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.label ?? v.sku ?? 'Option', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(Formatx.money(v.basePrice), style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (v.onOffer) ...[
                            const SizedBox(width: 6),
                            Text(Formatx.money(v.mrp),
                                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12, decoration: TextDecoration.lineThrough)),
                            const SizedBox(width: 6),
                            Text('${v.offPercent}% OFF',
                                style: const TextStyle(color: AppColors.cta, fontWeight: FontWeight.w800, fontSize: 12)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (_) {
                    final qty = cart.qtyFor(v.variantId);
                    return qty > 0
                        ? QtyStepper(
                            qty: qty,
                            onInc: () {
                              cart.increment(v.variantId).then((capped) {
                                if (capped && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 20 per item')));
                              });
                            },
                            onDec: () => cart.decrement(v.variantId),
                          )
                        : OutlinedButton(
                            onPressed: () => cart.add(toItem(detail, v)),
                            // Explicit bounded size: the global button theme is
                            // full-width (Size.fromHeight → minWidth=∞), which would
                            // force infinite width in this Row slot and blank the page.
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              foregroundColor: AppColors.cta,
                              side: const BorderSide(color: AppColors.cta, width: 1.4),
                            ),
                            child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.w900)),
                          );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Sticky bottom bar for simple products: price on left, ADD / stepper on right.
class _StickyBuyBar extends StatelessWidget {
  const _StickyBuyBar({
    required this.variant,
    required this.cart,
    required this.onAdd,
  });
  final Variant variant;
  final CartProvider cart;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final qty = cart.qtyFor(variant.variantId);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          Formatx.money(variant.basePrice),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        if (variant.onOffer) ...[
                          const SizedBox(width: 8),
                          Text(
                            Formatx.money(variant.mrp),
                            style: const TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 13,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (variant.onOffer)
                      Text(
                        'You save ${Formatx.money(variant.mrp - variant.basePrice)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: qty > 0
                    ? Padding(
                        key: const ValueKey('stepper'),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: QtyStepper(
                          dense: false,
                          qty: qty,
                          onInc: () {
                            cart.increment(variant.variantId).then((capped) {
                              if (capped && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 20 per item')));
                            });
                          },
                          onDec: () => cart.decrement(variant.variantId),
                        ),
                      )
                    : ElevatedButton(
                        key: const ValueKey('add'),
                        onPressed: onAdd,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(150, 50),
                        ),
                        child: const Text('ADD TO CART'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AppBar wishlist toggle for the shown product's (default) variant.
class _DetailHeartButton extends StatelessWidget {
  const _DetailHeartButton({required this.variantId});
  final int variantId;

  @override
  Widget build(BuildContext context) {
    final fav = context.select<WishlistProvider, bool>(
      (w) => w.contains(variantId),
    );
    return IconButton(
      tooltip: fav ? 'Remove from wishlist' : 'Add to wishlist',
      icon: Icon(
        fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: fav ? AppColors.danger : null,
      ),
      onPressed: () async {
        if (!context.read<AuthProvider>().isLoggedIn) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Log in to save items to your wishlist'),
            ),
          );
          context.push('/login');
          return;
        }
        try {
          await context.read<WishlistProvider>().toggle(variantId);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't update your wishlist")),
            );
          }
        }
      },
    );
  }
}

class _WriteReviewSheet extends StatefulWidget {
  const _WriteReviewSheet({required this.productId});
  final int productId;
  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _rating = 0;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _busy = false;
  bool _blocked = false; // permanently disabled after a non-retryable server rejection
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a star rating.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<CatalogRepository>().submitReview(
            widget.productId,
            _rating,
            _titleCtrl.text.trim(),
            _bodyCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review submitted — thank you!')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          // 409 conflicts are definitive — disable the button so the user
          // doesn't keep retrying (already reviewed / not yet received).
          if (e.isConflict) _blocked = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Write a Review',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    _rating >= star ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 36,
                    color: _rating >= star
                        ? const Color(0xFFFFA000)
                        : AppColors.inkSoft,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 191,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            decoration: const InputDecoration(
              labelText: 'Your review (optional)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: (_busy || _blocked) ? null : _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Submit Review'),
          ),
        ],
      ),
    );
  }
}
