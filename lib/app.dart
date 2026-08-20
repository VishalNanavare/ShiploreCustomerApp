import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/delivery_reconcile.dart';
import 'services/notification_service.dart';
import 'data/repositories/address_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/order_repository.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/location_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/wishlist_provider.dart';

class ShiploreApp extends StatefulWidget {
  const ShiploreApp({
    super.key,
    required this.auth,
    required this.location,
    required this.cart,
    required this.wishlist,
    required this.notifications,
    required this.catalogRepo,
    required this.orderRepo,
    required this.addressRepo,
    required this.customerRepo,
    required this.api,
  });

  final AuthProvider auth;
  final LocationProvider location;
  final CartProvider cart;
  final WishlistProvider wishlist;
  final NotificationProvider notifications;
  final CatalogRepository catalogRepo;
  final OrderRepository orderRepo;
  final AddressRepository addressRepo;
  final CustomerRepository customerRepo;
  final ApiClient api;

  @override
  State<ShiploreApp> createState() => _ShiploreAppState();
}

class _ShiploreAppState extends State<ShiploreApp> {
  late final AppRouter _router = AppRouter(widget.auth, widget.location);

  // App-level messenger so the delivery-area snackbar shows regardless of which
  // screen (or sheet) triggered the location change.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  // Last reconciled coordinates — guards against re-running on unrelated
  // LocationProvider notifications.
  double? _lastLat;
  double? _lastLng;

  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_syncWishlist);
    _syncWishlist();
    final loc = widget.location.location;
    _lastLat = loc?.lat;
    _lastLng = loc?.lng;
    widget.location.addListener(_onLocationChanged);

    // Push notifications: pass router + API client so tap-routing and token
    // registration both work, then init.
    NotificationService.setRouter(_router.router);
    NotificationService.setApiClient(widget.api);
    NotificationService.init();

    // Demo notification: fires 4 s after launch so the splash finishes first.
    Future.delayed(const Duration(seconds: 4), NotificationService.showDemo);

    // Clear the icon badge whenever the user brings the app to the foreground.
    _lifecycleListener = AppLifecycleListener(
      onResume: NotificationService.clearBadge,
    );
  }

  @override
  void dispose() {
    widget.auth.removeListener(_syncWishlist);
    widget.location.removeListener(_onLocationChanged);
    _lifecycleListener.dispose();
    super.dispose();
  }

  // Keep the wishlist in step with the session: load on login, clear on logout.
  // Also registers the FCM token with the backend on every login so the server
  // can send push notifications to this device.
  void _syncWishlist() {
    if (widget.auth.isLoggedIn) {
      widget.wishlist.ensureLoaded();
      NotificationService.registerToken();
    } else {
      widget.wishlist.clearLocal();
    }
  }

  // Any delivery-location change (map picker, current location, saved-address
  // pick, home auto-detect) reconciles the cart against the new spot, dropping
  // only the out-of-area shop's items (HR1) and notifying the customer.
  void _onLocationChanged() {
    final loc = widget.location.location;
    if (loc == null) return;
    if (loc.lat == _lastLat && loc.lng == _lastLng) return;
    _lastLat = loc.lat;
    _lastLng = loc.lng;
    if (widget.cart.isEmpty) return;
    reconcileCart(
      cart: widget.cart,
      repo: widget.orderRepo,
      lat: loc.lat,
      lng: loc.lng,
      onRemoved: (msg) => _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.location),
        ChangeNotifierProvider.value(value: widget.cart),
        ChangeNotifierProvider.value(value: widget.wishlist),
        ChangeNotifierProvider.value(value: widget.notifications),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        Provider.value(value: widget.catalogRepo),
        Provider.value(value: widget.orderRepo),
        Provider.value(value: widget.addressRepo),
        Provider.value(value: widget.customerRepo),
      ],
      child: MaterialApp.router(
        title: 'Shiplore',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: AppTheme.light(),
        routerConfig: _router.router,
      ),
    );
  }
}
