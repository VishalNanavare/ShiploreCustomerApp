import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../data/models/order.dart';
import '../../data/repositories/order_repository.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/states.dart';
import 'status_chip.dart';

// ── Filter tabs ────────────────────────────────────────────────────────────────

enum _Filter {
  all('All'),
  active('Active'),
  delivered('Delivered'),
  cancelled('Cancelled');

  const _Filter(this.label);
  final String label;

  static const _activeSet = {
    'created', 'confirmed', 'accepted', 'packed', 'ready',
    'out_for_delivery', 'picked_up', 'assigned', 'offered',
  };
  static const _deliveredSet = {'delivered', 'completed'};
  static const _cancelledSet = {'cancelled', 'failed'};

  bool matches(String status) {
    final s = status.toLowerCase();
    switch (this) {
      case _Filter.all: return true;
      case _Filter.active: return _activeSet.contains(s);
      case _Filter.delivered: return _deliveredSet.contains(s);
      case _Filter.cancelled: return _cancelledSet.contains(s);
    }
  }

  IconData get icon {
    switch (this) {
      case _Filter.all: return Icons.receipt_long_rounded;
      case _Filter.active: return Icons.local_shipping_rounded;
      case _Filter.delivered: return Icons.check_circle_rounded;
      case _Filter.cancelled: return Icons.cancel_rounded;
    }
  }

  Color get color {
    switch (this) {
      case _Filter.all: return AppColors.primary;
      case _Filter.active: return AppColors.cta;
      case _Filter.delivered: return AppColors.success;
      case _Filter.cancelled: return AppColors.danger;
    }
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  _Filter _filter = _Filter.all;
  String _query = '';

  final List<OrderModel> _all = [];
  int _page = 0;
  int _pages = 1;
  bool _loading = false;
  Object? _error;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _query = _searchCtrl.text.trim().toLowerCase());
      });
    });
    _scrollCtrl.addListener(_onScroll);
    _loadPage(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      if (!_loading && _page < _pages) _loadPage(_page + 1);
    }
  }

  Future<void> _loadPage(int page) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await context.read<OrderRepository>().orders(page: page);
      if (!mounted) return;
      setState(() {
        if (page == 1) _all.clear();
        _all.addAll(result.items);
        _page = page;
        _pages = result.pages;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e; });
    }
  }

  Future<void> _refresh() async {
    _page = 0;
    _pages = 1;
    await _loadPage(1);
  }

  List<OrderModel> _filtered(List<OrderModel> all) {
    return all.where((o) {
      if (!_filter.matches(o.status)) return false;
      if (_query.isEmpty) return true;
      if (o.orderNo.toLowerCase().contains(_query)) return true;
      for (final s in o.subOrders) {
        if ((s.vendor ?? '').toLowerCase().contains(_query)) return true;
        for (final it in s.items) {
          if (it.title.toLowerCase().contains(_query)) return true;
        }
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _all.isEmpty && _error == null) {
      return const _LoadingScaffold();
    }
    if (_error != null && _all.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My orders'),
          leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
        ),
        body: ErrorView(error: _error!, onRetry: _refresh),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.cta,
        child: _all.isEmpty
            ? CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  SliverAppBar(
                    title: const Text('My orders'),
                    leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyView(
                      title: 'No orders yet',
                      subtitle: 'Your first order will appear here.',
                      type: EmptyType.orders,
                      action: ElevatedButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Start shopping'),
                      ),
                    ),
                  ),
                ],
              )
            : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    final visible = _filtered(_all);
    final hasMore = _loading || _page < _pages;
    return CustomScrollView(
      controller: _scrollCtrl,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        _buildAppBar(_all.length),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickySearchDelegate(
            child: _SearchAndFilter(
              ctrl: _searchCtrl,
              selected: _filter,
              onFilter: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyFilter(query: _query, filter: _filter),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${visible.length} order${visible.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.separated(
              itemCount: visible.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                if (i >= visible.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return _OrderCard(order: visible[i]);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAppBar(int total) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      automaticallyImplyLeading: false,
      leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('My Orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('$total order${total != 1 ? 's' : ''} placed',
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          onPressed: _refresh,
          tooltip: 'Refresh',
        ),
      ],
    );
  }
}

// ── Sticky search + filter delegate ───────────────────────────────────────────

class _StickySearchDelegate extends SliverPersistentHeaderDelegate {
  const _StickySearchDelegate({required this.child});
  final Widget child;

  @override
  double get minExtent => 108;
  @override
  double get maxExtent => 108;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: AppColors.surface,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: Colors.black12,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickySearchDelegate old) => old.child != child;
}

// ── Search bar + filter chips ──────────────────────────────────────────────────

class _SearchAndFilter extends StatelessWidget {
  const _SearchAndFilter({required this.ctrl, required this.selected, required this.onFilter});
  final TextEditingController ctrl;
  final _Filter selected;
  final ValueChanged<_Filter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: ctrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search orders, items, shops…',
              hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkSoft, size: 20),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkSoft),
                      onPressed: ctrl.clear,
                    )
                  : null,
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.line, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _Filter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _Filter.values[i];
              final active = f == selected;
              return GestureDetector(
                onTap: () => onFilter(f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? f.color : AppColors.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? f.color : AppColors.line,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(f.icon,
                          size: 13,
                          color: active ? Colors.white : AppColors.inkSoft),
                      const SizedBox(width: 5),
                      Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Order Card ─────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final OrderModel order;

  static const _activeSet = {
    'created', 'confirmed', 'accepted', 'packed', 'ready',
    'out_for_delivery', 'picked_up', 'assigned', 'offered',
  };

  bool get _isActive => _activeSet.contains(order.status.toLowerCase());
  bool get _isDelivered =>
      order.status.toLowerCase() == 'delivered' || order.status.toLowerCase() == 'completed';
  bool get _isCancelled =>
      order.status.toLowerCase() == 'cancelled' || order.status.toLowerCase() == 'failed';

  Color get _accentColor {
    if (_isDelivered) return AppColors.success;
    if (_isCancelled) return AppColors.danger;
    if (_isActive) return AppColors.cta;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    // Pass the list summary so the detail screen paints header/status instantly.
    void track() => context.push('/track/${order.orderNo}', extra: order);

    // Collect up to 2 item titles + vendor list
    final allItems = order.subOrders.expand((s) => s.items).toList();
    final vendors = order.subOrders
        .map((s) => s.vendor)
        .where((v) => v != null && v.isNotEmpty)
        .toSet()
        .toList();
    final itemCount = allItems.fold<int>(0, (n, it) => n + it.qty.toInt());

    return ScaleTap(
      onTap: track,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
          border: Border(
            left: BorderSide(color: _accentColor, width: 3.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isDelivered
                          ? Icons.check_circle_rounded
                          : _isCancelled
                              ? Icons.cancel_rounded
                              : Icons.receipt_long_rounded,
                      color: _accentColor,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.orderNo,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(Formatx.date(order.placedAt),
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  StatusChip(status: order.status),
                ],
              ),
            ),
            // ── Item preview (only when sub-orders data is available)
            if (allItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...allItems.take(2).map((it) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 5, height: 5,
                                decoration: BoxDecoration(
                                    color: _accentColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  it.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('× ${it.qty.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontSize: 11.5, color: AppColors.inkSoft)),
                            ],
                          ),
                        )),
                    if (allItems.length > 2)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '+${allItems.length - 2} more item${allItems.length - 2 != 1 ? 's' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: _accentColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            // ── Shop pills (if vendor data available)
            if (vendors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: vendors
                      .take(3)
                      .map((v) => _VendorPill(name: v!))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ── Totals row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(Formatx.money(order.grandTotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
                  const SizedBox(width: 8),
                  if (itemCount > 0)
                    Text('· $itemCount item${itemCount != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                  // active badge
                  if (_isActive) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.cta.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.cta,
                              letterSpacing: 0.8)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Payment status strip (if unpaid + order still active).
            // Suppressed for terminal states: once an order is completed /
            // delivered / cancelled / returned the payment status is no longer
            // actionable by the customer and showing it is misleading.
            if ((order.paymentStatus ?? '').isNotEmpty &&
                order.paymentStatus!.toLowerCase() != 'paid' &&
                !const {'completed', 'delivered', 'cancelled', 'returned'}
                    .contains(order.status.toLowerCase())) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 13, color: Color(0xFFB45309)),
                    const SizedBox(width: 5),
                    Text(
                      'Payment ${order.paymentStatus!.replaceAll('_', ' ')}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 1, color: AppColors.line),
            // ── Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: track,
                    icon: Icon(Icons.local_shipping_outlined,
                        size: 16, color: _accentColor),
                    label: Text('Track',
                        style: TextStyle(
                            color: _accentColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _VendorPill extends StatelessWidget {
  const _VendorPill({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_rounded, size: 11, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(name,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ── Empty filter state ─────────────────────────────────────────────────────────

class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.query, required this.filter});
  final String query;
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final isSearch = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.bgTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearch ? Icons.search_off_rounded : filter.icon,
                size: 34,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'No results for "$query"' : 'No ${filter.label.toLowerCase()} orders',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              isSearch
                  ? 'Try a different order number, item or shop name.'
                  : 'Orders in this category will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading scaffold ──────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat(reverse: true);
  late final Animation<double> _anim =
      Tween<double>(begin: 0.4, end: 0.9).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

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
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _skel(42, 42, radius: 12),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _skel(160, 13),
                  const SizedBox(height: 6),
                  _skel(100, 10),
                ]),
              ]),
              const Spacer(),
              _skel(200, 11),
              const SizedBox(height: 6),
              _skel(140, 11),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skel(double w, double h, {double radius = 6}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppColors.line.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
