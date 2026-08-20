/// Central app configuration. Values are injected at build time via
/// `--dart-define` so no environment-specific value (or secret) is hard-coded.
///
/// Example:
///   flutter run \
///     --dart-define=API_BASE_URL=https://shiplorelocal.in/api/v1 \
///     --dart-define=CERT_SHA256=AA:BB:... \
///     --dart-define=GOOGLE_MAPS_API_KEY=...
class AppConfig {
  AppConfig._();

  /// Base URL of the CodeIgniter API (no trailing slash). HTTPS is enforced.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://shiplorelocal.in/api/v1',
  );

  /// Optional SHA-256 fingerprint of the server leaf/intermediate cert for
  /// certificate pinning. When empty, pinning is disabled (still HTTPS-only).
  /// Format: uppercase hex, colon-separated, e.g. "AB:CD:...".
  static const String certSha256 = String.fromEnvironment('CERT_SHA256', defaultValue: '');

  /// Maps API key (Android/iOS native config also required — see README).
  /// Inject at build time: --dart-define=GOOGLE_MAPS_API_KEY=AIzaSy...
  /// Map tiles are disabled when empty; GPS location picker still works.
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// 30-day JWT (matches AuthApiController::TTL). The app proactively refreshes.
  static const Duration tokenTtl = Duration(days: 30);

  static bool get isHttps => apiBaseUrl.startsWith('https://');
  static bool get pinningEnabled => certSha256.trim().isNotEmpty;

  /// Origin without the `/api/v1` suffix (media is served from the web root).
  static String get origin {
    final i = apiBaseUrl.indexOf('/api/');
    return i > 0 ? apiBaseUrl.substring(0, i) : apiBaseUrl;
  }

  /// Public media URL for an image uuid (route: GET /media/{uuid}).
  static String mediaUrl(String? uuid) => (uuid == null || uuid.isEmpty) ? '' : '$origin/media/$uuid';

  /// PayU CheckoutPro redirect URLs (must be reachable from the PayU SDK).
  static const String payuSuccessUrl = String.fromEnvironment(
    'PAYU_SUCCESS_URL',
    defaultValue: 'https://payuresponse.firebaseapp.com/success',
  );
  static const String payuFailureUrl = String.fromEnvironment(
    'PAYU_FAILURE_URL',
    defaultValue: 'https://payuresponse.firebaseapp.com/failure',
  );
}

