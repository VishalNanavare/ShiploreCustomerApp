import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/order_repository.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/states.dart';

/// Reason codes (shared with the backend) that mean "remove this item because it
/// can't be delivered to the chosen location".
const _deliveryReasons = {
  'not_deliverable',
  'outside_service_area',
  'shop_no_delivery',
  'no_serving_shop',
  'location_required',
};

/// Context-free core: re-validate [cart] against (lat,lng) and remove only the
/// items the server reports as undeliverable — items from other shops stay (HR1).
/// Calls [onRemoved] with a grouped message when anything was dropped. Fails
/// silent on network error so we never wrongly drop items. Returns whether the
/// cart still has items afterwards.
Future<bool> reconcileCart({
  required CartProvider cart,
  required OrderRepository repo,
  required double lat,
  required double lng,
  void Function(String message)? onRemoved,
}) async {
  if (cart.isEmpty) return false;

  List<Map<String, dynamic>> issues;
  try {
    final res = await repo.validateCart(cart.items, lat: lat, lng: lng);
    issues = res.issues;
  } catch (_) {
    return cart.items.isNotEmpty; // never drop items on a network failure
  }

  final removable =
      issues.where((i) => _deliveryReasons.contains(i['reason'])).toList();
  if (removable.isEmpty) return cart.items.isNotEmpty;

  final ids = removable
      .map((i) => (i['variant_id'] as num?)?.toInt())
      .whereType<int>()
      .toList();
  await cart.removeVariants(ids);
  onRemoved?.call(_removedSummary(removable));
  return cart.items.isNotEmpty;
}

/// Screen-facing wrapper: reads providers from [context] and shows the removal
/// notification via the nearest ScaffoldMessenger. Use from a mounted widget
/// (cart/checkout open). Returns whether the cart still has items.
Future<bool> reconcileCartForLocation(
  BuildContext context, {
  required double lat,
  required double lng,
}) {
  return reconcileCart(
    cart: context.read<CartProvider>(),
    repo: context.read<OrderRepository>(),
    lat: lat,
    lng: lng,
    onRemoved: (msg) {
      if (context.mounted) showSnack(context, msg, error: true);
    },
  );
}

/// "2 items removed — outside our delivery area. 1 item removed — …" grouped by
/// reason so multi-shop carts read accurately.
String _removedSummary(List<Map<String, dynamic>> removed) {
  final counts = <String, int>{};
  for (final r in removed) {
    final reason = (r['reason'] ?? '').toString();
    counts[reason] = (counts[reason] ?? 0) + 1;
  }
  return counts.entries
      .map((e) =>
          '${e.value} item${e.value == 1 ? '' : 's'} removed — ${_phrase(e.key)}.')
      .join(' ');
}

String _phrase(String reason) {
  switch (reason) {
    case 'outside_service_area':
      return 'outside our delivery area';
    case 'shop_no_delivery':
      return "the store doesn't deliver here";
    case 'no_serving_shop':
      return 'no store delivers them here';
    case 'location_required':
      return 'no delivery address pinned';
    default:
      return 'not available at this location';
  }
}
