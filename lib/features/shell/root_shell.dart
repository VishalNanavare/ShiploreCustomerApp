import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/cart_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../cart/cart_bar.dart';

/// App shell with a FLOATING Blinkit-style pill navigation bar (Home ·
/// Categories · Cart · Account). The body extends under it; the floating
/// "view cart" bar sits just above on the non-cart tabs.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Categories'),
    (Icons.shopping_cart_outlined, Icons.shopping_cart_rounded, 'Cart'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1.0,
  );
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.navigationShell.currentIndex;
  }

  @override
  void didUpdateWidget(RootShell old) {
    super.didUpdateWidget(old);
    final idx = widget.navigationShell.currentIndex;
    if (idx != _prevIndex) {
      _prevIndex = idx;
      _fade.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = widget.navigationShell.currentIndex;
    final offline = context.watch<ConnectivityProvider>().isOffline;
    return Scaffold(
      body: Column(
        children: [
          if (offline) const _OfflineBanner(),
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: widget.navigationShell,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (idx != 2) const CartBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x24101828), blurRadius: 20, offset: Offset(0, 8))],
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < RootShell._items.length; i++)
                      _NavItem(
                        icon: RootShell._items[i].$1,
                        activeIcon: RootShell._items[i].$2,
                        label: RootShell._items[i].$3,
                        selected: i == idx,
                        badge: i == 2
                            ? context.select<CartProvider, int>((c) => c.count)
                            : null,
                        onTap: () => widget.navigationShell.goBranch(i, initialLocation: i == idx),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap, this.badge});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.inkSoft;
    return Expanded(
      child: ScaleTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.cta.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? activeIcon : icon, size: 23, color: color),
                  if ((badge ?? 0) > 0)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          badge! > 99 ? '99+' : '$badge',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, height: 1.2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim banner shown across the shell when the device is offline.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text("You're offline — check your connection", style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
