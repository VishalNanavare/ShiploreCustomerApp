import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../core/utils/idgen.dart';
import '../../data/models/address.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/order.dart';
import '../../data/payments/payu_service.dart';
import '../../data/repositories/address_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/location_provider.dart';
import '../../widgets/network_image.dart';
import '../../widgets/qty_stepper.dart';
import '../../widgets/states.dart';

/// Delivery-instruction presets (Blinkit-style). Combined into one note string.
const _kInstructions = <(IconData, String)>[
  (Icons.notifications_off_outlined, "Don't ring the bell"),
  (Icons.phone_disabled_outlined, 'Avoid calling'),
  (Icons.meeting_room_outlined, 'Leave at the door'),
  (Icons.shield_outlined, 'Leave with the guard'),
];

const _kTipOptions = <int>[20, 30, 50];

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _idemKey = IdGen.idempotencyKey();
  final _couponCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  List<Address> _addresses = [];
  Address? _selected;
  Totals? _totals;
  List<Map<String, dynamic>> _issues = [];
  String? _appliedCoupon;
  String _method = 'cod'; // 'cod' | 'online'
  double _tip = 0;
  final Set<String> _tags = {};
  bool _showGstin = false;

  bool _loading = true;
  bool _validating = false;
  bool _placing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    _gstinCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  DeliveryLocation? get _loc => context.read<LocationProvider>().location;
  // When an address is explicitly selected we use ITS pin only — a saved address
  // with no coordinates must block (HR2: location_required), never silently fall
  // back to the browse location. Only with no selection do we use the browse pin.
  double? get _lat => _selected != null ? _selected!.latitude : _loc?.lat;
  double? get _lng => _selected != null ? _selected!.longitude : _loc?.lng;
  bool get _hasTarget => _lat != null && _lng != null;
  bool get _selectedHasNoPin =>
      _selected != null && (_selected!.latitude == null || _selected!.longitude == null);

  String get _instructions {
    final note = _noteCtrl.text.trim();
    return [..._tags, if (note.isNotEmpty) note].join('; ');
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _addresses = await context.read<AddressRepository>().list();
      if (_addresses.isNotEmpty) {
        _selected = _addresses.firstWhere(
          (a) => a.isDefault,
          orElse: () => _addresses.first,
        );
      }
      await _validate();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validate() async {
    if (!_hasTarget) {
      setState(() {
        _totals = null;
        _issues = [];
      });
      return;
    }
    setState(() => _validating = true);
    try {
      final cartItems = context.read<CartProvider>().items;
      final res = await context.read<OrderRepository>().validateCart(
        cartItems,
        lat: _lat,
        lng: _lng,
        coupon: _appliedCoupon,
        method: _method == 'online' ? 'payu' : 'cod',
        tip: _tip,
      );
      setState(() {
        _totals = res.totals;
        _issues = res.issues;
      });
      // Detect price changes: compare local cart unit prices vs server-returned prices.
      final changed = <Map<String, dynamic>>[];
      for (final line in res.lines) {
        final vid = (line['variant_id'] as num?)?.toInt();
        final serverPrice = (line['price'] as num?)?.toDouble();
        if (vid == null || serverPrice == null) continue;
        final local = cartItems.where((i) => i.variantId == vid).firstOrNull;
        if (local != null && (serverPrice - local.unitPrice).abs() > 0.01) {
          changed.add({'title': line['title'] ?? '', 'old': local.unitPrice, 'new': serverPrice});
        }
      }
      if (changed.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 22),
              SizedBox(width: 10),
              Text('Prices updated', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Some item prices changed since you added them to your cart:', style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                const SizedBox(height: 12),
                ...changed.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(c['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      const SizedBox(width: 8),
                      Text(Formatx.money(c['old']), style: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.inkSoft, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(Formatx.money(c['new']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.cta)),
                    ],
                  ),
                )),
              ],
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, e is ApiException ? e.message : 'Could not validate the cart.', error: true);
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Future<void> _applyCoupon(String code) async {
    if (code.trim().isEmpty) return;
    try {
      await context.read<OrderRepository>().validateCoupon(
        code.trim(),
        context.read<CartProvider>().items,
      );
      if (!mounted) return;
      setState(() => _appliedCoupon = code.trim().toUpperCase());
      _couponCtrl.clear();
      await _validate();
      if (mounted) showSnack(context, 'Coupon applied');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  void _removeCoupon() {
    setState(() => _appliedCoupon = null);
    _validate();
  }

  Future<void> _setTip(int amount) async {
    setState(() => _tip = _tip == amount ? 0 : amount.toDouble());
    await _validate();
  }

  Future<void> _customTip() async {
    final ctrl = TextEditingController(
      text: _tip > 0 ? _tip.toStringAsFixed(0) : '',
    );
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tip your delivery partner'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: 'Amount',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Add tip'),
          ),
        ],
      ),
    );
    if (v != null) {
      setState(() => _tip = v < 0 ? 0 : v);
      await _validate();
    }
  }

  Future<void> _seeCoupons() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CouponsSheet(repo: context.read<OrderRepository>()),
    );
    if (code != null) await _applyCoupon(code);
  }

  Future<void> _pickAddress() async {
    final chosen = await showModalBottomSheet<Address>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AddressSheet(addresses: _addresses, selected: _selected),
    );
    if (chosen != null) {
      setState(() => _selected = chosen);
      await _validate();
    } else if (mounted) {
      _init();
    }
  }

  Future<void> _place() async {
    if (!_hasTarget) {
      showSnack(
        context,
        _selectedHasNoPin
            ? 'Pin your delivery address on the map to continue.'
            : 'Choose a delivery address first.',
        error: true,
      );
      return;
    }
    // HR5: re-validate immediately before submit — the customer may have changed
    // the address or location since the last check.
    await _validate();
    if (!mounted) return;
    if (!_hasTarget || _issues.isNotEmpty) {
      showSnack(
        context,
        'Some items can’t be delivered here. Update your cart or address.',
        error: true,
      );
      return;
    }
    final user = context.read<AuthProvider>().user;
    final addr = _selected != null
        ? {
            'recipient_name': _selected!.recipientName ?? user?.name ?? '',
            'phone': _selected!.phone ?? user?.phone ?? '',
            'email': user?.email ?? '',
            'line1': _selected!.line1,
            'city': _selected!.city ?? '',
            'state_code': _selected!.stateCode ?? '27',
            'pincode': _selected!.pincode ?? '',
            'formatted_address': _selected!.formattedAddress ?? '',
          }
        : {
            'recipient_name': user?.name ?? '',
            'phone': user?.phone ?? '',
            'email': user?.email ?? '',
            'line1': _loc!.line1 ?? '',
            'city': _loc!.city ?? '',
            'state_code': _loc!.stateCode ?? '27',
            'pincode': _loc!.pincode ?? '',
            'formatted_address': _loc!.formatted ?? '',
          };

    final cart = context.read<CartProvider>();
    final orderRepo = context.read<OrderRepository>();
    final online = _method == 'online';
    setState(() => _placing = true);
    try {
      final placed = await orderRepo.placeOrder(
        items: cart.items,
        address: addr,
        lat: _lat!,
        lng: _lng!,
        method: online ? 'payu' : 'cod',
        coupon: _appliedCoupon,
        tip: _tip,
        gstin: _showGstin ? _gstinCtrl.text.trim() : null,
        deliveryInstructions: _instructions,
        idempotencyKey: _idemKey,
      );
      if (online) await _payOnline(orderRepo, placed.orderNo);
      await cart.clear();
      if (mounted) context.go('/order-success/${placed.orderNo}');
    } on ApiException catch (e) {
      // Server is the final gate (HR5): a delivery rejection arrives BEFORE any
      // payment path. Drop the offending item so the cart self-heals, then revalidate.
      if (!mounted) return;
      final reason = (e.details['reason'] ?? '').toString();
      final vid = (e.details['variant_id'] as num?)?.toInt();
      if (vid != null && _isDeliveryReason(reason)) {
        await cart.removeVariants([vid]);
        if (mounted) await _validate();
      }
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not place the order. Please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  static bool _isDeliveryReason(String reason) => const {
        'not_deliverable',
        'outside_service_area',
        'shop_no_delivery',
        'no_serving_shop',
        'location_required',
      }.contains(reason);

  /// Run the PayU CheckoutPro flow for a just-placed (unpaid) order. The order is
  /// already saved, so any outcome other than success just leaves it payable later.
  Future<void> _payOnline(OrderRepository repo, String orderNo) async {
    Map<String, dynamic> init;
    try {
      init = await repo.payInit(orderNo);
    } on ApiException catch (_) {
      if (mounted) {
        showSnack(context, 'Online payment is unavailable — your order is saved. Pay from My Orders.');
      }
      return;
    }
    final payu = PayUService(signHash: repo.payuHash);
    final res = await payu.pay(init: init);
    if (!mounted) return;
    if (res.outcome == PayUOutcome.success) {
      final paid = await repo.payVerify(orderNo, res.response);
      if (mounted) {
        showSnack(context, paid ? 'Payment successful' : 'Payment received — confirming shortly.');
      }
    } else if (res.outcome == PayUOutcome.cancelled) {
      showSnack(
        context,
        'Payment cancelled — your order is saved. Pay from My Orders.',
      );
    } else {
      showSnack(
        context,
        'Payment failed — your order is saved. Try again from My Orders.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyView(
          title: 'Your cart is empty',
          icon: Icons.shopping_cart_outlined,
          action: ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('Start shopping'),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/cart')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _CheckoutStepBar(
            hasAddress: _selected != null,
            isConfirming: _validating || _placing,
          ),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorView(error: _error!, onRetry: _init)
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children:
                  [
                        const _EtaBanner(),
                        const SizedBox(height: 12),
                        if (_selectedHasNoPin || !_hasTarget) ...[
                          _pinRequiredBanner(),
                          const SizedBox(height: 12),
                        ],
                        if (_issues.isNotEmpty) ...[
                          _issuesBanner(),
                          const SizedBox(height: 12),
                        ],
                        _shopGroups(cart),
                        const SizedBox(height: 12),
                        _couponCard(),
                        const SizedBox(height: 12),
                        _tipCard(),
                        const SizedBox(height: 12),
                        _billCard(),
                        const SizedBox(height: 12),
                        _gstinCard(),
                        const SizedBox(height: 12),
                        _instructionsCard(),
                        const SizedBox(height: 12),
                        _addressCard(),
                        const SizedBox(height: 12),
                        _paymentCard(),
                        const SizedBox(height: 12),
                        const _CancellationPolicy(),
                      ]
                      .animate(interval: 35.ms)
                      .fadeIn(duration: 240.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
            ),
      bottomNavigationBar: _loading || _error != null ? null : _placeBar(cart),
    );
  }

  // ---- sections ----

  Widget _section(
    String title,
    Widget child, {
    Widget? trailing,
    IconData? icon,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppShadows.card,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  /// Cart lines grouped by shop, each with a stepper + "save for later" heart.
  Widget _shopGroups(CartProvider cart) {
    final order = <int>[];
    final groups = <int, List<CartItem>>{};
    final names = <int, String>{};
    for (final it in cart.items) {
      final k = it.vendorId ?? 0;
      if (!groups.containsKey(k)) {
        order.add(k);
        groups[k] = [];
      }
      groups[k]!.add(it);
      final n = (it.vendorName ?? '').trim();
      names[k] = n.isEmpty ? 'Shiplore Store' : n;
    }
    return Column(
      children: [
        for (final k in order) ...[
          _section(
            names[k]!,
            icon: Icons.storefront_rounded,
            trailing: Text(
              '${groups[k]!.length} item${groups[k]!.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Column(children: [for (final it in groups[k]!) _line(cart, it)]),
          ),
          if (k != order.last) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _line(CartProvider cart, CartItem it) {
    final hasMrp = it.mrp > it.unitPrice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: AppImage(url: it.imageUrl, radius: 11),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if ((it.variantLabel ?? '').isNotEmpty)
                  Text(
                    it.variantLabel!,
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 11.5,
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      Formatx.money(it.unitPrice),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    if (hasMrp) ...[
                      const SizedBox(width: 6),
                      Text(
                        Formatx.money(it.mrp),
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
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
          QtyStepper(
            dense: true,
            qty: it.qty,
            onInc: () => cart.increment(it.variantId),
            onDec: () => cart.decrement(it.variantId),
          ),
        ],
      ),
    );
  }

  Widget _issuesBanner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.ctaTint,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.warning,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Some items can’t be delivered here',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              for (final i in _issues)
                Text(
                  '• ${i['title'] ?? 'An item'} — ${_reasonText((i['reason'] ?? '').toString())}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Shown when there's no usable delivery pin (no address chosen, or the chosen
  /// saved address has no coordinates) — payment stays disabled until fixed (HR2).
  Widget _pinRequiredBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wrong_location_outlined, color: AppColors.danger, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Pin your delivery address on the map to continue.',
                style: TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.35),
              ),
            ),
            TextButton(onPressed: _pickAddress, child: const Text('Choose')),
          ],
        ),
      );

  /// Canonical reason → customer copy (mirrors the backend DeliveryMessages).
  static String _reasonText(String reason) {
    switch (reason) {
      case 'outside_service_area':
        return 'outside our delivery area';
      case 'shop_no_delivery':
        return "the store doesn't deliver here";
      case 'no_serving_shop':
        return 'no store delivers it here';
      case 'location_required':
        return 'pin your address on the map';
      case 'payment_restricted':
        return 'not available for this payment method';
      case 'qty':
        return 'quantity unavailable';
      default:
        return 'unavailable at this location';
    }
  }

  Widget _couponCard() => _section(
    'Coupons & offers',
    icon: Icons.local_offer_outlined,
    trailing: TextButton(onPressed: _seeCoupons, child: const Text('See all')),
    _appliedCoupon != null
        ? Row(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '“$_appliedCoupon” applied',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: _removeCoupon, child: const Text('Remove')),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Enter coupon code',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                // Bounded size: the global theme makes buttons full-width
                // (minWidth=∞), which forces infinite width in a Row's non-flex
                // slot and blanks the screen.
                style: OutlinedButton.styleFrom(minimumSize: const Size(72, 44)),
                onPressed: _validating
                    ? null
                    : () => _applyCoupon(_couponCtrl.text),
                child: const Text('Apply'),
              ),
            ],
          ),
  );

  Widget _tipCard() => _section(
    'Tip your delivery partner',
    icon: Icons.volunteer_activism_outlined,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '100% of your tip goes to your delivery partner.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final t in _kTipOptions) ...[
              _tipChip('₹$t', _tip == t, () => _setTip(t)),
              const SizedBox(width: 8),
            ],
            _tipChip(
              _tip > 0 && !_kTipOptions.contains(_tip.toInt())
                  ? '₹${_tip.toStringAsFixed(0)}'
                  : 'Custom',
              _tip > 0 && !_kTipOptions.contains(_tip.toInt()),
              _customTip,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _tipChip(String label, bool selected, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ctaTint : AppColors.bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.cta : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: selected ? AppColors.ctaDark : AppColors.ink,
          ),
        ),
      ),
    ),
  );

  Widget _billRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: bold ? 2 : 4),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color ?? (bold ? AppColors.ink : AppColors.inkSoft),
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontSize: bold ? 16 : 13.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.ink,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            fontSize: bold ? 16 : 13.5,
          ),
        ),
      ],
    ),
  );

  Widget _billCard() {
    final t = _totals;
    return _section(
      'Bill details',
      icon: Icons.receipt_long_outlined,
      _validating
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : t == null
          ? const Text(
              'Set a delivery location to see the bill.',
              style: TextStyle(color: AppColors.inkSoft),
            )
          : Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Item total',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    if (t.savings > 0) ...[
                      Text(
                        Formatx.money(t.subtotal + t.savings),
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12.5,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      Formatx.money(t.subtotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                if (t.discount > 0)
                  _billRow(
                    'Coupon discount',
                    '- ${Formatx.money(t.discount)}',
                    color: AppColors.success,
                  ),
                _billRow(
                  'Delivery charge',
                  t.delivery <= 0 ? 'FREE' : Formatx.money(t.delivery),
                  color: t.delivery <= 0 ? AppColors.success : null,
                ),
                _billRow('Handling charge', Formatx.money(t.handling)),
                if (t.tip > 0) _billRow('Delivery tip', Formatx.money(t.tip)),
                const Divider(height: 22, color: AppColors.line),
                _billRow('To pay', Formatx.money(t.grand), bold: true),
                if (t.totalSavings > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'You save ${Formatx.money(t.totalSavings)} on this order',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _gstinCard() => _section(
    'Add GSTIN',
    icon: Icons.business_outlined,
    trailing: Switch(
      value: _showGstin,
      activeThumbColor: AppColors.primary,
      onChanged: (v) => setState(() => _showGstin = v),
    ),
    _showGstin
        ? TextField(
            controller: _gstinCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: '15-digit GSTIN',
              isDense: true,
            ),
          )
        : const Text(
            'Claim GST input credit on your business order.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
          ),
  );

  Widget _instructionsCard() => _section(
    'Delivery instructions',
    icon: Icons.edit_note_outlined,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (ic, label) in _kInstructions)
              _instructionChip(ic, label, _tags.contains(label), () {
                setState(
                  () => _tags.contains(label)
                      ? _tags.remove(label)
                      : _tags.add(label),
                );
              }),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteCtrl,
          minLines: 1,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Add a note for the delivery partner (optional)',
            isDense: true,
          ),
        ),
      ],
    ),
  );

  Widget _instructionChip(
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.bgTint : AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: selected ? AppColors.primary : AppColors.inkSoft,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _addressCard() {
    final hasAddr = _selected != null || (_loc != null);
    final line =
        _selected?.oneLine ?? _loc?.shortLabel ?? 'No delivery location set';
    final label = _selected?.label ?? _loc?.label ?? 'Deliver to';
    return _section(
      'Delivery address',
      icon: Icons.location_on_outlined,
      trailing: TextButton(
        onPressed: _pickAddress,
        child: const Text('Change'),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: const BoxDecoration(
              color: AppColors.bgTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasAddr ? line : 'Tap change to set your location',
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard() => _section(
    'Payment method',
    icon: Icons.account_balance_wallet_outlined,
    Column(
      children: [
        _payOption(
          'cod',
          Icons.payments_outlined,
          'Cash on Delivery',
          'Pay when your order arrives',
        ),
        const SizedBox(height: 10),
        _payOption(
          'online',
          Icons.account_balance_outlined,
          'Pay Online',
          'UPI · Cards · NetBanking (PayU)',
        ),
      ],
    ),
  );

  Widget _payOption(
    String value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _method == value;
    return GestureDetector(
      onTap: () {
        if (_method == value) return;
        setState(() => _method = value);
        _validate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.cta : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
          color: selected ? AppColors.ctaTint : AppColors.surface,
        ),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: AppColors.cta.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.cta, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.cta : AppColors.line,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeBar(CartProvider cart) {
    final canPlace =
        _hasTarget && _issues.isEmpty && !_validating && _totals != null;
    final grand = _totals?.grand ?? cart.subtotal;
    final label = _method == 'online'
        ? 'Pay ${Formatx.money(grand)}'
        : 'Place order';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.card,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'To pay',
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatx.money(grand),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canPlace && !_placing ? _place : null,
                  icon: _placing
                      ? const SizedBox.shrink()
                      : const Icon(Icons.lock_outline_rounded, size: 18),
                  label: _placing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Free-delivery promise banner at the top of the checkout.
class _EtaBanner extends StatelessWidget {
  const _EtaBanner();
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
          Expanded(
            child: Column(
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
          ),
        ],
      ),
    );
  }
}

/// Cancellation-policy note (Blinkit-style fine print).
class _CancellationPolicy extends StatelessWidget {
  const _CancellationPolicy();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Cancellation policy',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          SizedBox(height: 6),
          Text(
            'Orders can be cancelled per item before they are out for delivery; a full refund is issued for any cancelled or undelivered item.',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// "See all coupons" sheet — lists active public coupons; tap to apply.
class _CouponsSheet extends StatefulWidget {
  const _CouponsSheet({required this.repo});
  final OrderRepository repo;
  @override
  State<_CouponsSheet> createState() => _CouponsSheetState();
}

class _CouponsSheetState extends State<_CouponsSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.coupons();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available coupons',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        const Text(
                          'Could not load coupons.',
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() { _future = widget.repo.coupons(); }),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final coupons = snap.data ?? const [];
                if (coupons.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No coupons available right now.',
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final c in coupons)
                      _CouponTile(
                        code: '${c['code'] ?? ''}',
                        pct: (c['pct'] as num?)?.toDouble() ?? 0,
                        minOrder:
                            (c['min_order_value'] as num?)?.toDouble() ?? 0,
                        onApply: () =>
                            Navigator.pop(context, '${c['code'] ?? ''}'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({
    required this.code,
    required this.pct,
    required this.minOrder,
    required this.onApply,
  });
  final String code;
  final double pct;
  final double minOrder;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.ctaTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.ctaDark,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pct.toStringAsFixed(0)}% OFF',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                if (minOrder > 0)
                  Text(
                    'On orders above ${Formatx.money(minOrder)}',
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onApply, child: const Text('Apply')),
        ],
      ),
    );
  }
}

/// Inline saved-address picker (also links to add/manage).
class _AddressSheet extends StatelessWidget {
  const _AddressSheet({required this.addresses, this.selected});
  final List<Address> addresses;
  final Address? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select delivery address',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (addresses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No saved addresses yet.',
                  style: TextStyle(color: AppColors.inkSoft),
                ),
              ),
            ...addresses.map(
              (a) {
                final hasPin = a.latitude != null && a.longitude != null;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.id == selected?.id
                        ? Icons.radio_button_checked
                        : Icons.location_on_outlined,
                    color: hasPin ? AppColors.primary : AppColors.inkSoft,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!hasPin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warnSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.warnBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_off_rounded, size: 10, color: AppColors.warnText),
                              SizedBox(width: 3),
                              Text('No pin',
                                  style: TextStyle(color: AppColors.warnText, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.oneLine, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (!hasPin)
                        const Text(
                          'Edit this address and pin it on the map to use for delivery.',
                          style: TextStyle(color: AppColors.warnText, fontSize: 11),
                        ),
                    ],
                  ),
                  onTap: hasPin ? () => Navigator.pop(context, a) : null,
                );
              },
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/addresses');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Manage'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/location');
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutStepBar extends StatelessWidget {
  const _CheckoutStepBar({required this.hasAddress, required this.isConfirming});
  final bool hasAddress;
  final bool isConfirming;

  @override
  Widget build(BuildContext context) {
    final step = isConfirming ? 2 : (hasAddress ? 1 : 0);
    const labels = ['Address', 'Payment', 'Confirm'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: List.generate(5, (i) {
          if (i.isOdd) {
            // connector line
            final done = i ~/ 2 < step;
            return Expanded(
              child: Container(
                height: 2,
                color: done ? AppColors.cta : AppColors.line,
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < step;
          final active = idx == step;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done || active) ? AppColors.cta : AppColors.line,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                      : Text('${idx + 1}', style: TextStyle(color: (done || active) ? Colors.white : AppColors.inkSoft, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 3),
              Text(labels[idx], style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.cta : AppColors.inkSoft)),
            ],
          );
        }),
      ),
    );
  }
}
