import 'dart:convert';

import '../../core/utils/formatx.dart';

/// A line in the local cart (cart is held client-side; the server prices it at
/// validate/checkout time, so we never trust these prices for the order total).
class CartItem {
  CartItem({
    required this.variantId,
    required this.productId,
    required this.title,
    required this.slug,
    required this.unitPrice,
    required this.mrp,
    required this.imageUrl,
    this.variantLabel,
    this.vendorId,
    this.vendorName,
    this.qty = 1,
  });

  final int variantId;
  final int productId;
  final String title;
  final String slug;
  final double unitPrice;
  final double mrp;
  final String imageUrl;
  final String? variantLabel;
  final int? vendorId; // for grouping the cart/checkout by shop
  final String? vendorName;
  int qty;

  double get lineTotal => unitPrice * qty;
  double get lineSaving => (mrp > unitPrice ? mrp - unitPrice : 0.0) * qty;

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'product_id': productId,
        'title': title,
        'slug': slug,
        'unit_price': unitPrice,
        'mrp': mrp,
        'image_url': imageUrl,
        'variant_label': variantLabel,
        'vendor_id': vendorId,
        'vendor_name': vendorName,
        'qty': qty,
      };

  // Tolerant parsing (matches the other models): never hard-cast, so a schema
  // change or partially-corrupt prefs degrades one field instead of throwing.
  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        variantId: Formatx.toInt(j['variant_id']),
        productId: Formatx.toInt(j['product_id']),
        title: (j['title'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
        unitPrice: Formatx.toDouble(j['unit_price']),
        mrp: Formatx.toDouble(j['mrp']),
        imageUrl: (j['image_url'] ?? '').toString(),
        variantLabel: j['variant_label']?.toString(),
        vendorId: j['vendor_id'] == null ? null : Formatx.toInt(j['vendor_id']),
        vendorName: j['vendor_name']?.toString(),
        qty: Formatx.toInt(j['qty'], 1),
      );

  static String encodeList(List<CartItem> items) => jsonEncode(items.map((e) => e.toJson()).toList());

  static List<CartItem> decodeList(String? s) {
    if (s == null || s.isEmpty) return [];
    final raw = jsonDecode(s);
    if (raw is! List) return [];
    // Drop only individual bad entries — never discard the whole saved cart.
    final out = <CartItem>[];
    for (final e in raw) {
      try {
        out.add(CartItem.fromJson((e as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    return out;
  }
}
