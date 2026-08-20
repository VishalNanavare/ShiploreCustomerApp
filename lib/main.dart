import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/network/dev_http_overrides.dart';
import 'core/storage/secure_store.dart';
import 'data/repositories/address_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/order_repository.dart';
import 'data/repositories/wishlist_repository.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/location_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/wishlist_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug-only: route ALL HTTP (incl. cached image loads) to the dev server so
  // images/data resolve on an emulator/device. Compiled out of release.
  // Debug-only: bypass SSL cert verification so self-signed / locally-issued
  // server certs work on simulators and devices. Also optionally redirects the
  // TCP connection for the API host to DEV_HOST_IP (useful when the hostname
  // only resolves on the dev Mac's /etc/hosts). Never installed in release.
  const devIp = String.fromEnvironment('DEV_HOST_IP');
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides(Uri.parse(AppConfig.apiBaseUrl).host, devIp);
  }

  // Firebase powers phone-OTP login and crash reporting. Guarded so the rest
  // of the app still runs if config files haven't been added yet.
  try {
    await Firebase.initializeApp();
    // Route all uncaught Flutter + platform errors to Crashlytics in release.
    if (!kDebugMode) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init skipped (config missing?): $e');
  }

  // Single shared, secure HTTP client; repositories are thin wrappers over it.
  final api = ApiClient();
  final store = SecureStore();

  final auth = AuthProvider(api, store, AuthRepository(api));
  final location = LocationProvider();
  final cart = CartProvider();
  final wishlist = WishlistProvider(WishlistRepository(api));
  final customerRepo = CustomerRepository(api);

  // Restore session + cart + chosen location before first frame.
  await Future.wait([auth.bootstrap(), location.bootstrap(), cart.bootstrap()]);

  runApp(ShiploreApp(
    auth: auth,
    location: location,
    cart: cart,
    wishlist: wishlist,
    notifications: NotificationProvider(customerRepo),
    catalogRepo: CatalogRepository(api),
    orderRepo: OrderRepository(api),
    addressRepo: AddressRepository(api),
    customerRepo: customerRepo,
    api: api,
  ));
}
