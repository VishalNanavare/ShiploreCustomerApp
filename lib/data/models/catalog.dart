import '../../core/config/app_config.dart';
import '../../core/utils/formatx.dart';

/// A storefront category (carries hierarchy for the grouped Categories page).
class Category {
  Category({required this.name, required this.slug, this.id = 0, this.parentId, this.level = 0, this.imageUuid, this.cnt = 0});

  final int id;
  final int? parentId;
  final int level; // 0 = top group, 1 = sub-category, 2 = leaf
  final String name;
  final String slug;
  final String? imageUuid;
  final int cnt; // products in this category's whole subtree (0 → hide it)

  bool get hasProducts => cnt > 0;
  String get imageUrl => AppConfig.mediaUrl(imageUuid);

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: Formatx.toInt(j['id']),
        parentId: j['parent_id'] == null ? null : Formatx.toInt(j['parent_id']),
        level: Formatx.toInt(j['level']),
        name: (j['name'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
        imageUuid: (j['image_uuid'] ?? j['icon_uuid'])?.toString(),
        cnt: Formatx.toInt(j['cnt']),
      );
}

/// A nearby shop/store. Loosely modelled — keeps whatever the API provides.
class Shop {
  Shop({required this.id, required this.name, this.distanceKm, this.etaMin, this.businessType, this.imageUuid});

  final int id;
  final String name;
  final double? distanceKm;
  final int? etaMin;
  final String? businessType;
  final String? imageUuid;

  String get imageUrl => AppConfig.mediaUrl(imageUuid);

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
        id: Formatx.toInt(j['id']),
        name: (j['name'] ?? j['display_name'] ?? 'Store').toString(),
        distanceKm: j['distance_km'] == null ? null : Formatx.toDouble(j['distance_km']),
        etaMin: j['eta_min'] == null ? null : Formatx.toInt(j['eta_min']),
        businessType: (j['business_type'] as String?)?.trim(),
        imageUuid: (j['image_uuid'] ?? j['logo_uuid'])?.toString(),
      );
}
