import 'package:flutter/foundation.dart';

import '../data/models/product.dart';
import '../data/repositories/wishlist_repository.dart';

/// Account-synced wishlist state. Keeps a [Set] of wishlisted variant-ids for
/// instant heart toggling, plus the loaded products for the wishlist screen.
/// Loaded when the customer is logged in; cleared on logout.
class WishlistProvider extends ChangeNotifier {
  WishlistProvider(this._repo);
  final WishlistRepository _repo;

  final Set<int> _ids = {};
  List<Product> _items = [];
  bool _loading = false;
  bool _loaded = false;

  List<Product> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get isEmpty => _items.isEmpty;
  int get count => _ids.length;
  bool contains(int? variantId) => variantId != null && _ids.contains(variantId);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _repo.list();
      _ids
        ..clear()
        ..addAll(_items.map((p) => p.defaultVariantId ?? 0).where((v) => v > 0));
      _loaded = true;
    } catch (_) {
      // Not logged in / offline — leave the wishlist empty.
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!_loaded && !_loading) await load();
  }

  /// Optimistically toggle a variant. Returns the new state (true = wishlisted).
  Future<bool> toggle(int variantId) async {
    final was = _ids.contains(variantId);
    was ? _ids.remove(variantId) : _ids.add(variantId);
    notifyListeners();
    try {
      if (was) {
        await _repo.remove(variantId);
        _items.removeWhere((p) => (p.defaultVariantId ?? 0) == variantId);
      } else {
        await _repo.add(variantId);
        await load(); // pull the full product row for the wishlist screen
      }
    } catch (e) {
      was ? _ids.add(variantId) : _ids.remove(variantId); // revert on failure
      notifyListeners();
      rethrow;
    }
    return !was;
  }

  void clearLocal() {
    _ids.clear();
    _items = [];
    _loaded = false;
    notifyListeners();
  }
}
