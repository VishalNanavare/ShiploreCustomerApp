import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/about_screen.dart';
import '../../features/account/account_screen.dart';
import '../../features/account/addresses_screen.dart';
import '../../features/account/help_screen.dart';
import '../../features/account/notifications_screen.dart';
import '../../features/account/payments_screen.dart';
import '../../features/account/wallet_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/catalog/categories_screen.dart';
import '../../features/catalog/product_detail_screen.dart';
import '../../features/catalog/products_screen.dart';
import '../../features/checkout/checkout_screen.dart';
import '../../features/checkout/order_success_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/location/map_picker_screen.dart';
import '../../data/models/order.dart';
import '../../features/orders/order_track_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/shell/root_shell.dart';
import '../../features/shops/shops_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/wishlist/wishlist_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';

/// App routes. A bottom-nav shell (Home · Categories · Cart · Account) wraps the
/// four primary tabs; product/search/checkout/location push over it. Browsing is
/// public; checkout/orders/addresses/track require login. On first launch (no
/// saved delivery location) the router redirects to /location before browsing.
class AppRouter {
  AppRouter(this.auth, this.location);
  final AuthProvider auth;
  final LocationProvider location;

  static const _guarded = {'/checkout', '/orders', '/addresses'};

  /// Slide in from right with a secondary slide-left on the page beneath —
  /// the classic iOS push feel used throughout the app.
  static CustomTransitionPage<void> _slide(GoRouterState state, Widget child) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        child: child,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, anim, secondary, child) {
          final push = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          final pop = CurvedAnimation(parent: secondary, curve: Curves.easeInCubic);
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(push),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset.zero,
                end: const Offset(-0.25, 0),
              ).animate(pop),
              child: child,
            ),
          );
        },
      );

  late final GoRouter router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([auth, location]),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 56, color: Color(0xFFBBBBBB)),
            const SizedBox(height: 16),
            const Text('This page doesn\'t exist.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Splash drives its own navigation; never redirect away from it.
      if (loc == '/splash') return null;

      // No forced location gate: the app opens to Home and auto-detects the
      // delivery location in the background (Home._maybeAutoDetect). Until then
      // Home shows the full catalog with a "set location" bar.
      final needsAuth = _guarded.any((g) => loc == g || loc.startsWith('$g/')) ||
          loc.startsWith('/track') ||
          loc.startsWith('/order-success');
      if (needsAuth && !auth.isLoggedIn) {
        return '/login?redirect=${Uri.encodeComponent(state.uri.toString())}';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, s) => CustomTransitionPage<void>(
          key: s.pageKey,
          child: const SplashScreen(),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
      ),

      // Persistent bottom-nav shell wrapping the four primary tabs.
      // Fixed key so tab switches don't re-trigger the shell's fade transition.
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => CustomTransitionPage<void>(
          key: const ValueKey('root_shell'),
          child: RootShell(navigationShell: navigationShell),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (_, _) => const CartScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),

      // Routes pushed over the shell (cover the bottom nav).
      GoRoute(
        path: '/search',
        pageBuilder: (_, s) => _slide(s, ProductsScreen(
          initialQuery: s.uri.queryParameters['q'],
          category:     s.uri.queryParameters['category'],
          brand:        int.tryParse(s.uri.queryParameters['brand'] ?? ''),
          onOffer:      s.uri.queryParameters['on_offer'] == '1',
          minPrice:     double.tryParse(s.uri.queryParameters['min_price'] ?? ''),
          maxPrice:     double.tryParse(s.uri.queryParameters['max_price'] ?? ''),
          initialSort:  s.uri.queryParameters['sort'],
          label:        s.uri.queryParameters['label'],
        )),
      ),
      GoRoute(
        path: '/product/:slug',
        pageBuilder: (_, s) => _slide(s, ProductDetailScreen(slug: s.pathParameters['slug']!)),
      ),
      GoRoute(path: '/shops', pageBuilder: (_, s) => _slide(s, const ShopsScreen())),
      GoRoute(
        path: '/shop/:id',
        pageBuilder: (_, s) => _slide(s, ProductsScreen(
          shopId: int.tryParse(s.pathParameters['id'] ?? ''),
          title: s.uri.queryParameters['name'],
        )),
      ),
      GoRoute(path: '/location', pageBuilder: (_, s) => _slide(s, const MapPickerScreen())),
      GoRoute(path: '/login', pageBuilder: (_, s) => _slide(s, LoginScreen(redirect: s.uri.queryParameters['redirect']))),
      GoRoute(path: '/checkout', pageBuilder: (_, s) => _slide(s, const CheckoutScreen())),
      GoRoute(path: '/order-success/:orderNo', pageBuilder: (_, s) => _slide(s, OrderSuccessScreen(orderNo: s.pathParameters['orderNo']!))),
      GoRoute(path: '/orders', pageBuilder: (_, s) => _slide(s, const OrdersScreen())),
      GoRoute(path: '/wishlist', pageBuilder: (_, s) => _slide(s, const WishlistScreen())),
      GoRoute(path: '/track/:orderNo', pageBuilder: (_, s) => _slide(s, OrderTrackScreen(orderNo: s.pathParameters['orderNo']!, initial: s.extra is OrderModel ? s.extra as OrderModel : null))),
      GoRoute(path: '/addresses', pageBuilder: (_, s) => _slide(s, const AddressesScreen())),
      GoRoute(path: '/help', pageBuilder: (_, s) => _slide(s, const HelpScreen())),
      GoRoute(path: '/about', pageBuilder: (_, s) => _slide(s, const AboutScreen())),
      GoRoute(path: '/notifications', pageBuilder: (_, s) => _slide(s, const NotificationsScreen())),
      GoRoute(path: '/wallet', pageBuilder: (_, s) => _slide(s, const WalletScreen())),
      GoRoute(path: '/payments', pageBuilder: (_, s) => _slide(s, const PaymentsScreen())),
      // /menu — full-screen catalog browse; deep-linked from banners and notifications.
      GoRoute(path: '/menu', pageBuilder: (_, s) => _slide(s, const CategoriesScreen())),
    ],
  );
}
