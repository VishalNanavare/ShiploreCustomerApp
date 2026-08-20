import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/cart_item.dart';

/// Local cart (held client-side; the server reprices at validate/checkout).
class CartProvider extends ChangeNotifier {
  static const _key = 'cart_items';

  final List<CartItem> _items = [];
  bool _ready = false;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get ready => _ready;
  bool get isEmpty => _items.isEmpty;
  int get count => _items.fold(0, (s, i) => s + i.qty);
  double get subtotal => _items.fold(0.0, (s, i) => s + i.lineTotal);

  int qtyFor(int variantId) {
    for (final i in _items) {
      if (i.variantId == variantId) return i.qty;
    }
    return 0;
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _items
      ..clear()
      ..addAll(CartItem.decodeList(prefs.getString(_key)));
    _ready = true;
    notifyListeners();
  }

  Future<void> add(CartItem item) async {
    final idx = _items.indexWhere((i) => i.variantId == item.variantId);
    if (idx >= 0) {
      _items[idx].qty += item.qty;
    } else {
      _items.add(item);
    }
    await _save();
  }

  static const maxQtyPerItem = 20;

  /// Returns true if the qty was clamped at [maxQtyPerItem] (caller may show a snack).
  Future<bool> setQty(int variantId, int qty) async {
    final idx = _items.indexWhere((i) => i.variantId == variantId);
    if (idx < 0) return false;
    bool capped = false;
    if (qty <= 0) {
      _items.removeAt(idx);
    } else {
      if (qty > maxQtyPerItem) { qty = maxQtyPerItem; capped = true; }
      _items[idx].qty = qty;
    }
    await _save();
    return capped;
  }

  /// Returns true if the new quantity was clamped at [maxQtyPerItem].
  Future<bool> increment(int variantId) => setQty(variantId, qtyFor(variantId) + 1);
  Future<void> decrement(int variantId) => setQty(variantId, qtyFor(variantId) - 1);

  Future<void> clear() async {
    _items.clear();
    await _save();
  }

  /// Drop specific variants (used by delivery-area reconciliation — removes only
  /// the out-of-area shop's items, keeping everything else). No-op if none match.
  Future<void> removeVariants(List<int> variantIds) async {
    if (variantIds.isEmpty) return;
    final ids = variantIds.toSet();
    final before = _items.length;
    _items.removeWhere((i) => ids.contains(i.variantId));
    if (_items.length != before) await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, CartItem.encodeList(_items));
    notifyListeners();
  }
}
