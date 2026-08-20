# Shiplore — Customer App (Flutter)

A Blinkit-style quick-commerce customer app that consumes the Shiplore
CodeIgniter API (`/api/v1/customer/*` + `/api/v1/auth/*`).

> Flutter's language is **Dart** (native Android = Kotlin/Java, native iOS =
> Swift/Obj-C). This project is Dart/Flutter.

## Run

```bash
cd customer_app/shiplore
flutter pub get

# Point at your API + (optionally) pin the TLS cert. HTTPS is enforced.
flutter run \
  --dart-define=API_BASE_URL=https://test.eriklocal.online/api/v1 \
  --dart-define=CERT_SHA256=   # leave empty to disable pinning during dev
```

Release build (with code obfuscation + symbol stripping):

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1 \
  --dart-define=CERT_SHA256=AB:CD:EF:...   # production leaf/intermediate SHA-256
```

## Architecture

```
lib/
  core/        config, network (Dio client + interceptors), secure storage, theme, utils
  data/        models (typed fromJson) + repositories (thin API wrappers)
  providers/   AuthProvider, LocationProvider, CartProvider (ChangeNotifier)
  features/    home, catalog, cart, auth, account, location, common
  widgets/     shared UI (product card, qty stepper, states, image)
  app.dart     MultiProvider + MaterialApp.router
  main.dart    composition root (build deps, bootstrap, runApp)
```

State: `provider`. Routing: `go_router` (browse public; checkout/orders/addresses/track gated).

## Security model

- **Tokens** are stored only in `flutter_secure_storage` (iOS Keychain / Android
  Keystore-backed EncryptedSharedPreferences) — never `SharedPreferences`.
- **Transport**: HTTPS enforced; the client refuses a non-HTTPS base URL.
  Optional **certificate pinning** via `CERT_SHA256` (SHA-256 of the server cert).
- **Auth lifecycle**: every request carries the Bearer token; a `401` triggers a
  single `/auth/refresh`, retries once, and force-logs-out if refresh fails — so a
  revoked/expired/suspended-account token can't keep working (matches the server's
  per-request `isActive` re-check).
- **No secrets in source**: base URL, cert pin and Maps key are `--dart-define`s.
- **OTP**: the server only echoes the code in non-production; the app shows it as a
  dev convenience and never assumes it in release.
- **Client validation** mirrors the server (email/phone/pincode/lat-lng) as
  defense-in-depth; the server remains the source of truth.
- Recommended for release: `--obfuscate`, and (optional) `FLAG_SECURE` on order/
  payment screens to block screenshots.

## Build phases

| Phase | Scope | Status |
|------|-------|--------|
| 1 | Secure foundation (config, secure store, Dio client, theme, validators) | ✅ done |
| 2 | Auth (OTP + password, session, gate) | ✅ done |
| 3 | Location (GPS + map-pin picker, persisted lat/lng) | ✅ done |
| 4 | Catalog (home, search, product detail + variants) | ✅ done |
| 5 | Cart & checkout (validate, coupon, address, place order, success) | ✅ done |
| 6 | Orders & account (list, live track + rider, addresses CRUD, cancel/return) | ✅ done |
| 7 | Hardening & polish (map picker, cert pin, clean analyze) | ✅ done |

`flutter analyze` → **No issues found**. `flutter test` → all pass.

## Google Maps (optional, for the map-pin picker)

Maps render only when a key is configured; without one the app uses the GPS
picker (fully functional for deliverability).

- **App gate** (shows the "Pick on map" option): `--dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY`
- **Android render**: `flutter build apk -Pmaps_api_key=YOUR_KEY` (or set `maps_api_key`
  in `android/gradle.properties`) — injected into the manifest meta-data.
- **iOS render**: add `GMSServices.provideAPIKey("YOUR_KEY")` in `ios/Runner/AppDelegate.swift`
  and run `pod install` in `ios/`.

## API contract consumed

Public: `customer/home`, `customer/shops`, `customer/products`, `customer/product/{slug}`.
Auth (JWT): `auth/otp/request`, `auth/otp/verify`, `auth/login`, `auth/refresh`,
`customer/cart/validate`, `customer/coupons/validate`, `customer/orders` (place/list),
`customer/track/{no}`, `customer/orders/{no}/cancel-item/{subId}`,
`customer/orders/{no}/return`, `customer/addresses` (CRUD).
