import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/delivery_reconcile.dart';
import '../../core/utils/formatx.dart';
import '../../data/models/cart_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/location_provider.dart';
import '../../widgets/network_image.dart';
import '../../widgets/qty_stepper.dart';
import '../../widgets/states.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  DeliveryLocation? _lastLocation;

  @override
  void initState() {
    super.initState();
    // Reconcile on open (HR6): prune any item that no longer delivers to the
    // current location and notify, keeping items from other shops (HR1).
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileOnOpen());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = context.read<LocationProvider>().location;
    if (_lastLocation != null && loc != _lastLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileOnOpen());
    }
    _lastLocation = loc;
  }

  Future<void> _reconcileOnOpen() async {
    final loc = context.read<LocationProvider>().location;
    if (loc == null || !mounted) return;
    await reconcileCartForLocation(context, lat: loc.lat, lng: loc.lng);
  }

  double get _savings {
    final cart = context.read<CartProvider>();
    return cart.items.fold(0.0, (s, i) => s + i.lineSaving);
  }

  /// Cart lines grouped under a per-shop header (one "bill" per shop), so the
  /// customer sees exactly which store each item ships from.
  List<Widget> _buildShopGroups(CartProvider cart) {
    final order = <int>[];
    final groups = <int, List<CartItem>>{};
    final names = <int, String>{};
    for (final it in cart.items) {
      final key = it.vendorId ?? 0;
      if (!groups.containsKey(key)) {
        order.add(key);
        groups[key] = [];
      }
      groups[key]!.add(it);
      final n = (it.vendorName ?? '').trim();
      names[key] = n.isEmpty ? 'Shiplore Store' : n;
    }
    final widgets = <Widget>[];
    for (var g = 0; g < order.length; g++) {
      final items = groups[order[g]]!;
      widgets.add(
        _ShopHeader(
          name: names[order[g]]!,
          count: items.length,
        ).animate().fadeIn(delay: (g * 40).ms, duration: 240.ms),
      );
      for (final it in items) {
        widgets.add(
          Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CartLine(
                  item: it,
                  onInc: () {
                    cart.increment(it.variantId).then((capped) {
                      if (capped && context.mounted) showSnack(context, 'Maximum 20 per item');
                    });
                  },
                  onDec: () => cart.decrement(it.variantId),
                ),
              )
              .animate()
              .fadeIn(duration: 220.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: cart.isEmpty
          ? EmptyView(
              title: 'Your cart is empty',
              subtitle: 'Add items to get started.',
              type: EmptyType.cart,
              action: ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Start shopping'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: [
                const _EtaStrip(),
                const SizedBox(height: 14),
                ..._buildShopGroups(cart),
                const SizedBox(height: 4),
                _BillSummary(
                  subtotal: cart.subtotal,
                  savings: _savings,
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 8),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(subtotal: cart.subtotal),
    );
  }
}

/// Quick-commerce promise: bold ETA chip near the top of the cart.
class _EtaStrip extends StatelessWidget {
  const _EtaStrip();

  @override
  Widget build(BuildContext context) {
    final etaMin = context.watch<LocationProvider>().nearestEtaMin;
    final etaText = etaMin != null ? 'Delivery in ~$etaMin mins' : 'Fast delivery';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.ctaTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.cta,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                etaText,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Shipped from the nearest store',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-shop header above a group of cart lines (Blinkit "shipment from X").
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.bgTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 17,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            '$count item${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.inkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single cart line as a floating, shadowed card.
class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.onInc,
    required this.onDec,
  });

  final CartItem item;
  final VoidCallback onInc;
  final VoidCallback onDec;

  @override
  Widget build(BuildContext context) {
    final hasMrp = item.mrp > item.unitPrice;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: AppImage(url: item.imageUrl, radius: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                if ((item.variantLabel ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.variantLabel!,
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      Formatx.money(item.unitPrice),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (hasMrp) ...[
                      const SizedBox(width: 6),
                      Text(
                        Formatx.money(item.mrp),
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          QtyStepper(qty: item.qty, onInc: onInc, onDec: onDec),
        ],
      ),
    );
  }
}

/// Bill details with a highlighted savings row.
class _BillSummary extends StatelessWidget {
  const _BillSummary({required this.subtotal, required this.savings});

  final double subtotal;
  final double savings;

  @override
  Widget build(BuildContext context) {
    final itemTotal = subtotal + savings;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bill details',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          _row('Item total', Formatx.money(itemTotal)),
          if (savings > 0) ...[
            const SizedBox(height: 8),
            _row('You save', '- ${Formatx.money(savings)}', highlight: true),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.line),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              Text(
                Formatx.money(subtotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    final color = highlight ? AppColors.success : AppColors.inkSoft;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: color,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            color: highlight ? AppColors.success : AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Sticky checkout bar — subtotal on the left, amber CTA on the right.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.subtotal});

  final double subtotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.card,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
                  Text(
                    Formatx.money(subtotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.push('/checkout'),
                  child: const Text('Proceed to checkout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
