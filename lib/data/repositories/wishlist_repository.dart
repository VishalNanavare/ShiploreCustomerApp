import '../../core/network/api_client.dart';
import '../models/product.dart';

/// Account-synced wishlist (backend `wishlists`/`wishlist_items`, variant-keyed).
/// Items come back Product-shaped so the shared [ProductCard] renders them.
class WishlistRepository {
  WishlistRepository(this._api);
  final ApiClient _api;

  Future<List<Product>> list() async {
    final res = await _api.getPage('/customer/wishlist');
    return ((res.data as List?) ?? const [])
        .map((e) => Product.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> add(int variantId) => _api.post('/customer/wishlist', body: {'variant_id': variantId});

  Future<void> remove(int variantId) => _api.delete('/customer/wishlist/$variantId');
}
