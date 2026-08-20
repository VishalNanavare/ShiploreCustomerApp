import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../data/models/order.dart';
import '../../data/repositories/order_repository.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'status_chip.dart';

class OrderTrackScreen extends StatefulWidget {
  const OrderTrackScreen({super.key, required this.orderNo, this.initial});
  final String orderNo;
  /// Summary order passed from the list so the header/status/step-bar paint
  /// instantly while the full detail (sub-orders) loads behind a skeleton.
  final OrderModel? initial;
  @override
  State<OrderTrackScreen> createState() => _OrderTrackScreenState();
}

class _OrderTrackScreenState extends State<OrderTrackScreen> with WidgetsBindingObserver {
  late Future<OrderModel> _future;
  OrderModel? _order; // latest loaded order, kept in place for flicker-free polling
  bool _detailLoaded = false; // true once the full track() (with sub-orders) has arrived

  static const _cancellable = {'created', 'confirmed', 'accepted', 'packed', 'ready'};
  static const _returnable = {'delivered', 'completed'};
  static const _terminal = {'delivered', 'completed', 'cancelled', 'returned', 'refunded', 'failed'};
  static const _maxRetries = 2;
  static const _pollInterval = Duration(seconds: 20);

  Timer? _pollTimer;
  bool _foregrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _order = widget.initial; // paint the summary instantly if the list handed one over
    _future = _loadWithRetry()..then(_onLoaded).ignore();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foregrounded = state == AppLifecycleState.resumed;
    if (_foregrounded) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  bool _isTerminal(OrderModel o) => _terminal.contains(o.status.toLowerCase());

  void _onLoaded(OrderModel o) {
    if (!mounted) return;
    setState(() {
      _order = o;
      _detailLoaded = true;
    });
    if (_isTerminal(o)) {
      _pollTimer?.cancel();
    } else {
      _startPolling();
    }
  }

  void _startPolling() {
    if (!_foregrounded) return;
    final o = _order;
    if (o != null && _isTerminal(o)) return;
    if (_pollTimer?.isActive ?? false) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  /// Background refresh — updates data in place without the loading spinner.
  Future<void> _pollOnce() async {
    final o = _order;
    if (o != null && _isTerminal(o)) {
      _pollTimer?.cancel();
      return;
    }
    try {
      final fresh = await _loadWithRetry();
      _onLoaded(fresh);
    } catch (_) {
      // Background poll failures are silent; the next tick retries.
    }
  }

  /// Retries up to [_maxRetries] times on transient network errors. Short delay —
  /// the ApiClient already does its own exponential-backoff retry, so this is just a
  /// thin safety net and must not pile multiple seconds onto first paint.
  Future<OrderModel> _loadWithRetry({int attempt = 0}) async {
    final repo = context.read<OrderRepository>();
    try {
      return await repo.track(widget.orderNo);
    } on ApiException {
      rethrow; // server errors (4xx/5xx) surface immediately
    } catch (e) {
      if (attempt < _maxRetries) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) rethrow;
        return _loadWithRetry(attempt: attempt + 1);
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final f = _loadWithRetry();
    setState(() { _future = f; });
    _onLoaded(await f);
  }

  Future<void> _cancel(SubOrder s) async {
    final repo = context.read<OrderRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel item?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('"${s.items.isNotEmpty ? s.items.first.title : s.subOrderNo}" will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.cancelItem(widget.orderNo, s.subOrderId);
      if (!mounted) return;
      showSnack(context, 'Item cancelled');
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _return(SubOrder s) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReturnSheet(orderNo: widget.orderNo, sub: s),
    );
    if (result == true) {
      if (mounted) showSnack(context, 'Return requested');
      _refresh();
    }
  }

  Future<void> _cancelWholeOrder() async {
    final repo = context.read<OrderRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel entire order?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('All items will be cancelled. A refund will be processed if applicable.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel order'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.cancelOrder(widget.orderNo);
      if (!mounted) return;
      showSnack(context, 'Order cancelled');
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _rateDelivery(int deliveryId) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RatingSheet(deliveryId: deliveryId),
    );
    if (result == true) {
      if (mounted) showSnack(context, 'Thank you for rating!');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrderModel>(
      future: _future,
      builder: (context, snap) {
        // Prefer the in-place order so background polling updates render without
        // flashing the full-screen spinner; fall back to the future's snapshot.
        final o = _order ?? snap.data;
        if (o == null && snap.connectionState == ConnectionState.waiting) {
          // A layout-matching skeleton (not a spinner) so the wait reads as intentional
          // and never as a blank/broken screen — the dark header + order no stay visible.
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(widget.orderNo,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            body: const _TrackSkeleton(),
          );
        }
        if (o == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order tracking')),
            body: ErrorView(error: snap.error ?? 'Order not found', onRetry: _refresh),
          );
        }
        final nearestEta = _soonestEta(o.subOrders);
        final allCancellable = o.subOrders.isNotEmpty &&
            o.subOrders.every((s) => _cancellable.contains(s.status.toLowerCase()));
        final ratingDeliveryIds = o.subOrders
            .where((s) => (s.delivery?.status?.toLowerCase() == 'delivered') && s.delivery?.id != null)
            .map((s) => s.delivery!.id!)
            .toList();

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.cta,
            child: CustomScrollView(
              slivers: [
                _SliverOrderBar(order: o, onRefresh: _refresh),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusBanner(status: o.status, eta: nearestEta),
                      const SizedBox(height: 12),
                      _StepBar(status: o.status, subOrders: o.subOrders),
                      const SizedBox(height: 12),
                      _MetaStrip(order: o),
                      const SizedBox(height: 16),
                      if (_detailLoaded) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            '${o.subOrders.length} shop group${o.subOrders.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColors.inkSoft,
                                letterSpacing: 0.4),
                          ),
                        ),
                        ...o.subOrders.map((s) => _SubCard(
                              sub: s,
                              canCancel: _cancellable.contains(s.status.toLowerCase()),
                              canReturn: _returnable.contains(s.status.toLowerCase()),
                              onCancel: () => _cancel(s),
                              onReturn: () => _return(s),
                            )),
                        _BillSummary(order: o),
                        if (o.returns.isNotEmpty) _ReturnsSection(returns: o.returns),
                      ] else
                        // Header/status/step-bar are already painted from the list summary;
                        // only the per-shop detail is still loading → skeleton just that.
                        const _SubCardsLoading(),
                      if (allCancellable) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _cancelWholeOrder,
                              icon: const Icon(Icons.cancel_outlined, size: 16),
                              label: const Text('Cancel Entire Order'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                minimumSize: const Size(0, 44),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                      for (final deliveryId in ratingDeliveryIds) ...[
                        const SizedBox(height: 12),
                        _RateDeliveryCard(
                          deliveryId: deliveryId,
                          onRate: () => _rateDelivery(deliveryId),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _HelpRow(orderNo: o.orderNo),
                      const SizedBox(height: 36),
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
}

// ── Sliver App Bar ─────────────────────────────────────────────────────────────

class _SliverOrderBar extends StatelessWidget {
  const _SliverOrderBar({required this.order, required this.onRefresh});
  final OrderModel order;
  final VoidCallback onRefresh;

  void _showInvoice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InvoiceSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = (order.paymentStatus ?? '').toLowerCase() == 'paid' ||
        const {'completed', 'delivered'}.contains(order.status.toLowerCase());
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: AppColors.primary,
      centerTitle: false,
      // Always show a back button — when there is nothing to pop (e.g. user
      // arrived via order-success which reset the stack), fall back to /orders.
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/account');
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(order.orderNo,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(Formatx.date(order.placedAt),
              style: const TextStyle(fontSize: 10.5, color: Colors.white60, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: [
        if (isPaid)
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Colors.white70, size: 20),
            onPressed: () => _showInvoice(context),
            tooltip: 'Invoice',
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
          onPressed: onRefresh,
          tooltip: 'Refresh',
        ),
      ],
    );
  }
}

// ── Status Banner ──────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, this.eta});
  final String status;
  final String? eta;

  static const _done = {'delivered', 'completed'};
  static const _cancelled = {'cancelled', 'failed'};
  static const _riding = {'out_for_delivery', 'picked_up', 'assigned', 'offered'};

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color bg;
    final IconData icon;
    final String headline;
    final String sub;

    if (_done.contains(s)) {
      bg = AppColors.success;
      icon = Icons.check_circle_rounded;
      headline = 'Order Delivered!';
      sub = 'Hope you love your purchase';
    } else if (_cancelled.contains(s)) {
      bg = AppColors.danger;
      icon = Icons.cancel_rounded;
      headline = s == 'failed' ? 'Delivery Failed' : 'Order Cancelled';
      sub = 'Contact support if you need help';
    } else if (_riding.contains(s)) {
      bg = AppColors.cta;
      icon = Icons.delivery_dining_rounded;
      headline = 'On the way to you!';
      final etaText = _etaText(eta);
      sub = etaText != null ? 'ETA: $etaText' : 'Your order is out for delivery';
    } else {
      bg = AppColors.primary;
      icon = Icons.inventory_2_rounded;
      headline = _headlineFor(s);
      sub = 'Sit back while we prepare your order';
    }

    final isActive = !_done.contains(s) && !_cancelled.contains(s);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 3),
                Text(sub,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 10),
            _PulseDot(color: Colors.white),
          ],
        ],
      ),
    );
  }

  String _headlineFor(String s) {
    switch (s) {
      case 'confirmed': return 'Order Confirmed';
      case 'accepted': return 'Accepted by Store';
      case 'packed': case 'ready': return 'Packed & Ready';
      default: return 'Order Placed';
    }
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _anim =
      Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}

// ── Horizontal Step Bar ────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  const _StepBar({required this.status, this.subOrders = const []});
  final String status;
  final List<SubOrder> subOrders;

  static const _steps = [
    (label: 'Placed', icon: Icons.receipt_long_rounded),
    (label: 'Packed', icon: Icons.inventory_2_rounded),
    (label: 'On way', icon: Icons.delivery_dining_rounded),
    (label: 'Done', icon: Icons.check_circle_rounded),
  ];

  /// Maps a status to its step index (-1 = cancelled, 0 = placed … 3 = done).
  static int _stepFor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered': case 'completed': return 3;
      case 'out_for_delivery': case 'picked_up': case 'assigned': case 'offered': return 2;
      case 'packed': case 'ready': return 1;
      case 'cancelled': case 'failed': return -1;
      default: return 0;
    }
  }

  int get _current {
    final s = status.toLowerCase();
    // For a partially-fulfilled order, follow the furthest-progressed
    // non-cancelled sub-order rather than collapsing to step 0.
    if (s == 'partially_fulfilled') {
      final steps = subOrders
          .map((sub) => _stepFor(sub.status))
          .where((step) => step >= 0);
      return steps.isEmpty ? 0 : steps.reduce((a, b) => a > b ? a : b);
    }
    if (s == 'returned' || s == 'refunded') return 3;
    return _stepFor(s);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final cancelled = current < 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _StepNode(
              step: _steps[i],
              done: !cancelled && i <= current,
              active: !cancelled && i == current,
              cancelled: cancelled && i == 0,
            ),
            if (i < _steps.length - 1)
              Expanded(
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: (!cancelled && i < current) ? AppColors.success : AppColors.line,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({required this.step, required this.done, required this.active, required this.cancelled});
  final ({String label, IconData icon}) step;
  final bool done;
  final bool active;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final col = cancelled
        ? AppColors.danger
        : done
            ? AppColors.success
            : AppColors.line;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: done ? col.withValues(alpha: 0.12) : AppColors.bg,
            shape: BoxShape.circle,
            border: Border.all(color: col, width: active ? 2.5 : 1.5),
          ),
          child: Icon(
            cancelled ? Icons.close_rounded : step.icon,
            size: 17,
            color: done ? col : AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          step.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: done ? AppColors.ink : AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ── Meta Strip ─────────────────────────────────────────────────────────────────

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final paid = order.paymentStatus?.toLowerCase() == 'paid';
    final terminal = const {'completed', 'delivered', 'cancelled', 'returned'}
        .contains(order.status.toLowerCase());
    // Muted for terminal orders — payment status is informational only once
    // the order is done; amber warning only makes sense while it's still active.
    final paymentColor = paid
        ? AppColors.success
        : terminal
            ? AppColors.inkSoft
            : const Color(0xFFB54708);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip(Icons.access_time_rounded, Formatx.date(order.placedAt), AppColors.inkSoft),
          const SizedBox(width: 8),
          _chip(
            paid ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
            (order.paymentStatus ?? 'pending').toUpperCase(),
            paymentColor,
          ),
          const Spacer(),
          Text(
            Formatx.money(order.grandTotal),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ── Sub-order Card ─────────────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.sub,
    required this.canCancel,
    required this.canReturn,
    required this.onCancel,
    required this.onReturn,
  });
  final SubOrder sub;
  final bool canCancel;
  final bool canReturn;
  final VoidCallback onCancel;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final d = sub.delivery;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Store header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              color: AppColors.bgTint,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: AppColors.line, width: 0.8)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.vendor ?? sub.subOrderNo,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(sub.subOrderNo,
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                    ],
                  ),
                ),
                StatusChip(status: sub.status),
              ],
            ),
          ),
          // ── Items
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(children: sub.items.map(_ItemRow.new).toList()),
          ),
          // ── Sub-total row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                const Text('Sub-total',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(Formatx.money(sub.grandTotal),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(color: AppColors.line, height: 1),
          ),
          // ── Rider / delivery tile
          if (d != null && (d.status != null || d.hasRider)) _RiderTile(delivery: d),
          // ── Delivery OTP (shown only when out for delivery)
          if (sub.status.toLowerCase() == 'out_for_delivery' && sub.deliveryOtp != null)
            _OtpTile(otp: sub.deliveryOtp!),
          // ── Actions
          if (canCancel || canReturn)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text('Cancel item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        minimumSize: const Size(0, 36),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  if (canReturn)
                    OutlinedButton.icon(
                      onPressed: onReturn,
                      icon: const Icon(Icons.assignment_return_rounded, size: 14),
                      label: const Text('Return'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item, {super.key});
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(color: AppColors.cta, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if ((item.sku ?? '').isNotEmpty)
                  Text(item.sku!,
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('× ${item.qty.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5)),
              Text(Formatx.money(item.unitPrice * item.qty),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiderTile extends StatelessWidget {
  const _RiderTile({required this.delivery});
  final DeliveryInfo delivery;

  @override
  Widget build(BuildContext context) {
    final etaText = _etaText(delivery.eta);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.ctaTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cta.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.cta.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delivery_dining_rounded, color: AppColors.cta, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label(delivery.status),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  if (delivery.hasRider)
                    Text(delivery.riderName!,
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                  if (etaText != null)
                    Text('ETA: $etaText',
                        style: const TextStyle(
                            color: AppColors.cta, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (delivery.hasRider && (delivery.riderPhone ?? '').isNotEmpty)
              Material(
                color: AppColors.cta,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showCallDialog(context, delivery.riderName!, delivery.riderPhone!),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.call_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _label(String? s) {
    switch (s) {
      case 'pending': return 'Awaiting delivery partner';
      case 'assigned': return 'Partner assigned';
      case 'picked_up': return 'Picked up from store';
      case 'out_for_delivery': return 'Out for delivery';
      case 'delivered': return 'Delivered';
      case 'failed': return 'Delivery failed';
      case 'returned': return 'Returned to store';
      default: return 'Preparing your order';
    }
  }
}

// ── Delivery OTP Tile ─────────────────────────────────────────────────────────

class _OtpTile extends StatelessWidget {
  const _OtpTile({required this.otp});
  final String otp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Delivery OTP',
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    otp,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 6, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Text(
              'Share with\nyour rider',
              style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bill Summary ───────────────────────────────────────────────────────────────

class _BillSummary extends StatelessWidget {
  const _BillSummary({required this.order});
  final OrderModel order;

  double get _itemsTotal => order.subOrders.fold(
      0.0, (s, sub) => s + sub.items.fold(0.0, (ss, it) => ss + it.unitPrice * it.qty));

  @override
  Widget build(BuildContext context) {
    final items = _itemsTotal;
    final grand = order.grandTotal;
    final charges = grand - items;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          _row('Items total', items),
          if (charges > 0.5) _row('Delivery & charges', charges),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppColors.line, height: 1),
          ),
          Row(
            children: [
              const Text('Grand Total',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
              const Spacer(),
              Text(Formatx.money(grand),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          const Spacer(),
          Text(Formatx.money(value),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );
  }
}

// ── Returns Section ────────────────────────────────────────────────────────────

class _ReturnsSection extends StatelessWidget {
  const _ReturnsSection({required this.returns});
  final List<ReturnRequest> returns;

  static const _statusColors = {
    'requested': Color(0xFFFFA000),
    'approved': Color(0xFF1976D2),
    'refunded': Color(0xFF388E3C),
    'rejected': Color(0xFFD32F2F),
  };

  static const _statusLabels = {
    'requested': 'Requested',
    'approved': 'Approved',
    'refunded': 'Refunded',
    'rejected': 'Rejected',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_return_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Return Requests',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          ...returns.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            final color = _statusColors[r.status] ?? const Color(0xFF757575);
            final label = _statusLabels[r.status] ?? r.status;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: AppColors.line, height: 1),
                  ),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                    const Spacer(),
                    Text(Formatx.date(r.createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.inkSoft)),
                  ],
                ),
                const SizedBox(height: 10),
                ...r.items.map((it) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${it.qty.toStringAsFixed(0)}× ${it.title}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.ink),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(Formatx.money(it.refundAmount),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                        ],
                      ),
                    )),
                if (r.items.length > 1) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: AppColors.line, height: 1),
                  ),
                  Row(
                    children: [
                      const Text('Total refund',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const Spacer(),
                      Text(Formatx.money(r.totalRefund),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ],
                if ((r.customerNote ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Note: ${r.customerNote}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                          fontStyle: FontStyle.italic)),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Help Row ───────────────────────────────────────────────────────────────────

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.orderNo});
  final String orderNo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/help'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Need help with this order?',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('Get support from our team',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ETA formatting ─────────────────────────────────────────────────────────────

/// Soonest future ETA across all sub-orders (raw ISO string), or null if every
/// ETA is missing or already in the past.
String? _soonestEta(List<SubOrder> subOrders) {
  final now = DateTime.now();
  DateTime? soonest;
  String? soonestRaw;
  for (final s in subOrders) {
    final raw = s.delivery?.eta;
    if (raw == null || raw.isEmpty) continue;
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null || !dt.isAfter(now)) continue;
    if (soonest == null || dt.isBefore(soonest)) {
      soonest = dt;
      soonestRaw = raw;
    }
  }
  return soonestRaw;
}

/// Human-friendly ETA: past → "Arriving any moment", near-term → "in N min",
/// otherwise the absolute date. Returns null for empty/unparseable input.
String? _etaText(String? eta) {
  final s = eta?.toString();
  if (s == null || s.isEmpty) return null;
  final dt = DateTime.tryParse(s);
  if (dt == null) return s;
  final diff = dt.toLocal().difference(DateTime.now());
  if (diff.isNegative) return 'Arriving any moment';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes < 1 ? 1 : diff.inMinutes} min';
  return Formatx.date(eta);
}

// ── Rider call dialog ──────────────────────────────────────────────────────────

void _showCallDialog(BuildContext context, String name, String phone) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: AppColors.cta.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.delivery_dining_rounded, color: AppColors.cta, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Delivery Partner',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.ctaTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cta.withValues(alpha: 0.3)),
            ),
            child: Text(phone,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.cta,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dial this number from your phone\'s dialer to contact your delivery partner.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: phone));
            Navigator.pop(context);
            showSnack(context, 'Number copied — open your dialer to call');
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy number'),
        ),
      ],
    ),
  );
}

// ── Rate Delivery Card ─────────────────────────────────────────────────────────

class _RateDeliveryCard extends StatelessWidget {
  const _RateDeliveryCard({required this.deliveryId, required this.onRate});
  final int deliveryId;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rate your delivery',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text('Tell us how the delivery went',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onRate,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            child: const Text('Rate'),
          ),
        ],
      ),
    );
  }
}

// ── Rating Sheet ───────────────────────────────────────────────────────────────

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({required this.deliveryId});
  final int deliveryId;
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      showSnack(context, 'Please select a star rating', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<OrderRepository>().rateDelivery(
            widget.deliveryId,
            _rating,
            comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rate your delivery',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('How was your delivery experience?',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    _rating >= star ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 40,
                    color: _rating >= star ? const Color(0xFFFFC107) : AppColors.inkSoft,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'e.g. Fast delivery, friendly rider…',
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Rating'),
          ),
        ],
      ),
    );
  }
}

// ── Return Sheet ───────────────────────────────────────────────────────────────

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.orderNo, required this.sub});
  final String orderNo;
  final SubOrder sub;
  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _reason = TextEditingController();
  final Map<int, bool> _checked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final it in widget.sub.items) {
      _checked[it.orderItemId] = true;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final items = widget.sub.items
        .where((it) => _checked[it.orderItemId] == true)
        .map((it) => {'order_item_id': it.orderItemId, 'qty': it.qty})
        .toList();
    if (items.isEmpty) {
      showSnack(context, 'Select at least one item', error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      showSnack(context, 'Please add a reason', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context
          .read<OrderRepository>()
          .returnItems(widget.orderNo, items, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Request a Return',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('Select items you want to return',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          const SizedBox(height: 12),
          ...widget.sub.items.map((it) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _checked[it.orderItemId] ?? false,
                onChanged: (v) => setState(() => _checked[it.orderItemId] = v ?? false),
                title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Qty ${it.qty.toStringAsFixed(0)} · ${Formatx.money(it.unitPrice)}'),
                activeColor: AppColors.primary,
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason for return',
              hintText: 'e.g. Wrong item, damaged product…',
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Return Request'),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────
// Mirrors the real layout (status banner → step bar → meta → shop-group cards) so
// first paint never looks blank/broken while the order is fetched.

// Just the per-shop card region (used once the header/status are already painted
// from the list summary and only the order detail is still loading).
class _SubCardsLoading extends StatelessWidget {
  const _SubCardsLoading();

  @override
  Widget build(BuildContext context) {
    return Shimmery(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 110, height: 12), // "N shop groups"
            SizedBox(height: 12),
            _SubCardSkeleton(),
            SizedBox(height: 14),
            _SubCardSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _TrackSkeleton extends StatelessWidget {
  const _TrackSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmery(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SkeletonBox(height: 70, radius: 16), // status banner
          const SizedBox(height: 18),
          Row( // step bar: 4 stages
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              4,
              (_) => const Column(children: [
                SkeletonBox(width: 38, height: 38, radius: 19),
                SizedBox(height: 6),
                SkeletonBox(width: 44, height: 8),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const SkeletonBox(height: 46, radius: 12), // meta strip
          const SizedBox(height: 20),
          const SkeletonBox(width: 120, height: 12), // "N shop groups"
          const SizedBox(height: 12),
          const _SubCardSkeleton(),
          const SizedBox(height: 14),
          const _SubCardSkeleton(),
        ],
      ),
    );
  }
}

class _SubCardSkeleton extends StatelessWidget {
  const _SubCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SkeletonBox(width: 40, height: 40, radius: 10),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 150, height: 13),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 10),
              ]),
            ),
            SkeletonBox(width: 64, height: 22, radius: 11),
          ]),
          SizedBox(height: 16),
          SkeletonBox(height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: 210, height: 12),
          SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            SkeletonBox(width: 70, height: 12),
            SkeletonBox(width: 54, height: 12),
          ]),
        ],
      ),
    );
  }
}

// ── Invoice Sheet ──────────────────────────────────────────────────────────────

class _InvoiceSheet extends StatelessWidget {
  const _InvoiceSheet({required this.order});
  final OrderModel order;

  String get _dateStr {
    final s = order.placedAt ?? '';
    final dt = DateTime.tryParse(s);
    return dt == null ? s : DateFormat('d MMM yyyy, h:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final addr = order.billingAddress;
    final addrLine = (addr['formatted'] as String?) ?? (addr['line1'] as String?) ?? '';
    final customerName = (addr['name'] as String?) ?? '';
    final phone = (addr['phone'] as String?) ?? '';
    final paid = (order.paymentStatus ?? '').toLowerCase() == 'paid';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TAX INVOICE',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary,
                                letterSpacing: 0.5)),
                        Text('Shiplore',
                            style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: paid ? AppColors.success.withValues(alpha: 0.12) : const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        paid ? 'PAID' : 'PENDING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: paid ? AppColors.success : const Color(0xFF856404),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _infoBlock('Invoice #', order.orderNo),
                    ),
                    Expanded(
                      child: _infoBlock('Date', _dateStr),
                    ),
                  ],
                ),
                if (customerName.isNotEmpty || phone.isNotEmpty || addrLine.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BILL TO',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft, letterSpacing: 0.7)),
                        const SizedBox(height: 6),
                        if (customerName.isNotEmpty)
                          Text(customerName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (phone.isNotEmpty)
                          Text(phone,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                        if (addrLine.isNotEmpty)
                          Text(addrLine,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Items list
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                ...order.subOrders.map((sub) => _VendorBlock(sub: sub)),
                const SizedBox(height: 8),
                _TotalsBlock(order: order),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft, letterSpacing: 0.7)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      );
}

class _VendorBlock extends StatefulWidget {
  const _VendorBlock({required this.sub});
  final SubOrder sub;

  @override
  State<_VendorBlock> createState() => _VendorBlockState();
}

class _VendorBlockState extends State<_VendorBlock> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await context.read<OrderRepository>().invoicePdfBytes(widget.sub.subOrderId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${widget.sub.subOrderNo}.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Invoice ${widget.sub.subOrderNo}');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } catch (_) {
      // Share sheet dismissed / print cancelled — no user-visible error needed.
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.sub;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: AppColors.bgTint,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(sub.vendor ?? sub.subOrderNo,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                          color: AppColors.ink)),
                ),
                Text(sub.subOrderNo,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
                if (sub.invoiceId != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _download,
                    child: _downloading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.primary))
                        : const Icon(Icons.download_rounded, size: 16, color: AppColors.primary),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                // Column headers
                const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text('ITEM', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft, letterSpacing: 0.6)),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('QTY', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                              color: AppColors.inkSoft, letterSpacing: 0.6)),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text('PRICE', textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                              color: AppColors.inkSoft, letterSpacing: 0.6)),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text('TOTAL', textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                              color: AppColors.inkSoft, letterSpacing: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: AppColors.line),
                const SizedBox(height: 6),
                ...sub.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                        color: AppColors.ink)),
                                if ((item.sku ?? '').isNotEmpty)
                                  Text(item.sku!,
                                      style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              item.qty == item.qty.truncateToDouble()
                                  ? item.qty.toInt().toString()
                                  : item.qty.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: AppColors.ink),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(Formatx.money(item.unitPrice),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(Formatx.money(item.unitPrice * item.qty),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 4),
                const Divider(height: 1, color: AppColors.line),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Spacer(),
                    const Text('Sub-total: ',
                        style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
                    Text(Formatx.money(sub.grandTotal),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final itemsTotal = order.subOrders.fold(
        0.0, (s, sub) => s + sub.items.fold(0.0, (ss, it) => ss + it.unitPrice * it.qty));
    // Use model fields when available (detail load), fall back to computed items total.
    final subtotal = order.subtotal > 0 ? order.subtotal : itemsTotal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _row('Items Total', subtotal),
          if (order.discountTotal > 0)
            _row('Discount', -order.discountTotal, color: AppColors.success),
          if (order.taxTotal > 0) _row('GST', order.taxTotal),
          if (order.deliveryTotal > 0) _row('Delivery', order.deliveryTotal),
          if (order.handlingTotal > 0) _row('Platform Fee', order.handlingTotal),
          if (order.tipTotal > 0) _row('Tip', order.tipTotal),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppColors.line, height: 1),
          ),
          Row(
            children: [
              const Text('Grand Total',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
              const Spacer(),
              Text(Formatx.money(order.grandTotal),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: 13, color: color ?? AppColors.inkSoft)),
            const Spacer(),
            Text(
              value < 0 ? '- ${Formatx.money(-value)}' : Formatx.money(value),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color ?? AppColors.ink),
            ),
          ],
        ),
      );
}
