import '../../core/config/app_config.dart';
import '../../core/utils/formatx.dart';

/// A purchasable variant of a product (product detail screen).
class Variant {
  Variant({
    required this.variantId,
    this.sku,
    required this.basePrice,
    required this.mrp,
    this.label,
    this.isDefault = false,
    this.stock,
  });

  final int variantId;
  final String? sku;
  final double basePrice;
  final double mrp;
  final String? label;
  final bool isDefault;
  final double? stock;

  bool get onOffer => mrp > basePrice;
  int get offPercent => onOffer ? (((mrp - basePrice) / mrp) * 100).round() : 0;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        variantId: Formatx.toInt(j['variant_id'] ?? j['id']),
        sku: j['sku']?.toString(),
        basePrice: Formatx.toDouble(j['base_price']),
        mrp: Formatx.toDouble(j['mrp']),
        label: j['label']?.toString(),
        isDefault: Formatx.toInt(j['is_default']) == 1,
        stock: j['stock'] == null ? null : Formatx.toDouble(j['stock']),
      );
}

/// A catalog product as returned by home/products list endpoints.
class Product {
  Product({
    required this.id,
    required this.title,
    required this.slug,
    this.productType = 'simple',
    this.category,
    this.vendor,
    this.vendorId,
    required this.basePrice,
    required this.mrp,
    this.defaultVariantId,
    this.variantCount = 1,
    this.imageUuid,
  });

  final int id;
  final String title;
  final String slug;
  final String productType;
  final String? category;
  final String? vendor;
  final int? vendorId;
  final double basePrice;
  final double mrp;
  final int? defaultVariantId;
  final int variantCount;
  final String? imageUuid;

  bool get hasVariants => productType == 'variant' && variantCount > 1;
  bool get onOffer => mrp > basePrice;
  int get offPercent => onOffer ? (((mrp - basePrice) / mrp) * 100).round() : 0;
  String get imageUrl => AppConfig.mediaUrl(imageUuid);

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: Formatx.toInt(j['id']),
        title: (j['title'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
        productType: (j['product_type'] ?? 'simple').toString(),
        category: j['category']?.toString(),
        vendor: j['vendor']?.toString(),
        vendorId: j['vendor_id'] == null ? null : Formatx.toInt(j['vendor_id']),
        basePrice: Formatx.toDouble(j['base_price']),
        mrp: Formatx.toDouble(j['mrp']),
        defaultVariantId: j['variant_id'] == null ? null : Formatx.toInt(j['variant_id']),
        variantCount: Formatx.toInt(j['variant_count'], 1),
        imageUuid: j['image_uuid']?.toString(),
      );
}

class ProductReview {
  const ProductReview({
    required this.rating,
    required this.author,
    this.title,
    this.body,
    this.createdAt,
  });

  final int rating;
  final String author;
  final String? title;
  final String? body;
  final String? createdAt;

  factory ProductReview.fromJson(Map<String, dynamic> j) => ProductReview(
        rating: (j['rating'] is num) ? (j['rating'] as num).toInt() : int.tryParse(j['rating']?.toString() ?? '') ?? 0,
        author: j['author']?.toString() ?? 'Anonymous',
        title: j['title']?.toString(),
        body: j['body']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// Full product detail (product/{slug}).
class ProductDetail {
  ProductDetail({
    required this.product,
    required this.variants,
    required this.images,
    this.description,
    this.highlights = const [],
    this.related = const [],
    this.reviews = const [],
  });

  final Product product;
  final List<Variant> variants;
  final List<String> images; // resolved media urls
  final String? description;
  final List<String> highlights;
  final List<Product> related;
  final List<ProductReview> reviews;

  int get variantCount => variants.length;
  double get avgRating => reviews.isEmpty ? 0 : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

  factory ProductDetail.fromJson(Map<String, dynamic> j) {
    final p = (j['product'] as Map).cast<String, dynamic>();
    final variants = ((j['variants'] as List?) ?? const [])
        .map((e) => Variant.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final images = ((j['images'] as List?) ?? const [])
        .map((e) => AppConfig.mediaUrl(((e as Map)['uuid'] ?? e['image_uuid'])?.toString()))
        .where((u) => u.isNotEmpty)
        .toList();
    final highlights = ((j['highlights'] as List?) ?? const [])
        .map((e) => (e is Map ? (e['text'] ?? e['title'] ?? e['value']) : e).toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final related = ((j['related'] as List?) ?? const [])
        .map((e) => Product.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final reviews = ((j['reviews'] as List?) ?? const [])
        .map((e) => ProductReview.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return ProductDetail(
      product: Product.fromJson(p),
      variants: variants,
      images: images,
      description: p['description']?.toString(),
      highlights: highlights,
      related: related,
      reviews: reviews,
    );
  }
}
