import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_client.dart';

// Must be top-level — Dart VM calls this in an isolated background context.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService._showLocal(message);
}

// Top-level handler for notification taps when the app was killed.
// flutter_local_notifications requires this to be top-level + annotated.
// Navigation happens when the app relaunches: getInitialMessage() covers FCM,
// and the NotificationAppLaunchDetails path covers local notification taps.
@pragma('vm:entry-point')
void notificationBackgroundTapHandler(NotificationResponse response) {
  // Store the route so the foreground init path can consume it.
  // The router isn't available yet in a background isolate, so we write to
  // a shared global that NotificationService.init() drains on launch.
  _pendingTapRoute = response.payload;
}

// Package-private: drained once by NotificationService.init() on app start.
String? _pendingTapRoute;

class NotificationService {
  // ── Channels ───────────────────────────────────────────────────────────────
  // Two channels so users can independently mute promos without losing order alerts.
  static const _ordersId   = 'shiplore_orders';
  static const _ordersName = 'Orders & Delivery';
  static const _promoId    = 'shiplore_promos';
  static const _promoName  = 'Offers & Promotions';

  // ── Brand tokens ───────────────────────────────────────────────────────────
  // Orange matches AppColors.cta = 0xFFF5821F.
  static const _orange = Color(0xFFF5821F);
  // Distinctive double-buzz so the user knows it's a delivery alert.
  static final _vibrate = Int64List.fromList([0, 180, 80, 220]);

  static final _local = FlutterLocalNotificationsPlugin();
  static GoRouter? _router;
  static void setRouter(GoRouter r) => _router = r;

  static ApiClient? _api;
  static void setApiClient(ApiClient api) => _api = api;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    await _local.initialize(
      const InitializationSettings(
        // Use the white monochrome icon — 'ic_stat_notify' from drawable/.
        // Using the launcher icon here makes a solid coloured square appear in
        // the Android status bar (looks very unprofessional on Android 5+).
        android: AndroidInitializationSettings('ic_stat_notify'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundTapHandler,
    );

    final ap = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // High-priority channel for orders — badge, vibration, max importance.
    await ap?.createNotificationChannel(AndroidNotificationChannel(
      _ordersId,
      _ordersName,
      description: 'Real-time updates on your Shiplore orders and deliveries.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibrate,
      showBadge: true,
    ));

    // Lower-priority channel for promos — silent by default, user can promote.
    await ap?.createNotificationChannel(const AndroidNotificationChannel(
      _promoId,
      _promoName,
      description: 'Deals, discounts and exclusive offers from Shiplore.',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    ));

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showLocal);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleFcmTap(initial);

    // Local notification tap while app was killed: drain the global written
    // by notificationBackgroundTapHandler before the router was available.
    final details = await _local.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final route = details!.notificationResponse?.payload;
      if (route != null && route.isNotEmpty) {
        // Post-frame so the router tree is mounted before navigation.
        WidgetsBinding.instance.addPostFrameCallback((_) => _router?.push(route));
      }
    } else if (_pendingTapRoute != null) {
      final route = _pendingTapRoute!;
      _pendingTapRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _router?.push(route));
    }

    await FirebaseMessaging.instance.subscribeToTopic('all');
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => registerToken());
  }

  // ── Backend token registration ─────────────────────────────────────────────

  static Future<void> registerToken() async {
    if (_api == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _api!.post('customer/device-token', body: {
        'fcm_token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
      debugPrint('[FCM] token registered with backend');
    } catch (e) {
      debugPrint('[FCM] token registration failed: $e');
    }
  }

  // ── Demo notification ──────────────────────────────────────────────────────

  /// Fire a rich sample notification to show the full UI —
  /// no backend or FCM connection required.
  static Future<void> showDemo() async {
    await _local.show(
      9999,
      'Your order is almost here! \u{1F6F5}',
      'Order #SHP-1042 · Arriving in ~8 min',
      NotificationDetails(
        android: _buildAndroid(
          channelId: _ordersId,
          channelName: _ordersName,
          title: 'Your order is almost here! \u{1F6F5}',
          expandedBody:
              '✅ Order Confirmed\n'
              '✅ Items Packed by Store\n'
              '\u{1F6F5} Out for Delivery — Rahul is on his way\n'
              '\u{1F4CD} Arriving in ~8 minutes · ETA 6:15 PM',
          summary: 'Shiplore · Order #SHP-1042',
          withTrackButton: true,
        ),
        iOS: const DarwinNotificationDetails(
          badgeNumber: 1,
          subtitle: 'Order #SHP-1042 · ETA 8 min',
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: '/orders',
    );
  }

  // ── FCM → local ────────────────────────────────────────────────────────────

  static Future<void> _showLocal(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    final data  = message.data;
    final badge = _parseBadge(data['badge']);
    // Badge update removed (app_badge_plus removed to avoid KGP build warning).

    final isPromo   = (data['type'] as String?) == 'promotion';
    final route     = data['route'] as String?;
    final expanded  = _buildExpandedBody(data, n.body ?? '');

    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: isPromo
            ? _buildPromoAndroid(title: n.title ?? '', body: n.body ?? '')
            : _buildAndroid(
                channelId: _ordersId,
                channelName: _ordersName,
                title: n.title ?? '',
                expandedBody: expanded,
                summary: 'Shiplore',
                withTrackButton: true,
              ),
        iOS: DarwinNotificationDetails(
          badgeNumber: badge,
          presentAlert: true,
          presentBadge: !isPromo,
          presentSound: !isPromo,
        ),
      ),
      payload: route,
    );
  }

  // ── Notification builders ─────────────────────────────────────────────────

  /// Rich order/delivery notification: white icon, brand orange, BigText expand,
  /// large app icon on right, vibration, optional Track Order action.
  static AndroidNotificationDetails _buildAndroid({
    required String channelId,
    required String channelName,
    required String title,
    required String expandedBody,
    required String summary,
    bool withTrackButton = false,
  }) =>
      AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.max,
        priority: Priority.high,
        // White lightning bolt — renders cleanly in status bar on all Android versions.
        icon: 'ic_stat_notify',
        // Orange accent tint applied to the notification card header.
        color: _orange,
        // App logo shown as a large badge on the right side of the notification.
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(
          expandedBody,
          htmlFormatBigText: false,
          contentTitle: title,
          htmlFormatContentTitle: false,
          summaryText: summary,
          htmlFormatSummaryText: false,
        ),
        actions: withTrackButton
            ? const [
                AndroidNotificationAction(
                  'track_order',
                  'Track Order',
                  showsUserInterface: true,
                  cancelNotification: false,
                ),
              ]
            : const [],
        // 'Shiplore' shown below the timestamp in the collapsed view.
        subText: 'Shiplore',
        ticker: title,
        channelShowBadge: true,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _vibrate,
        category: AndroidNotificationCategory.transport,
        autoCancel: true,
      );

  /// Minimal promo notification: lower importance, no vibration, no badge.
  static AndroidNotificationDetails _buildPromoAndroid({
    required String title,
    required String body,
  }) =>
      AndroidNotificationDetails(
        _promoId,
        _promoName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_stat_notify',
        color: _orange,
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Shiplore Offers',
        ),
        subText: 'Shiplore',
        channelShowBadge: false,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.promo,
        autoCancel: true,
      );

  // Build an expanded body from FCM data fields (order/delivery events).
  static String _buildExpandedBody(Map<String, dynamic> data, String fallback) {
    final status  = data['status']   as String?;
    final orderNo = data['order_no'] as String?;
    final eta     = data['eta']      as String?;
    final rider   = data['rider']    as String?;

    if (status == null && orderNo == null) return fallback;

    final buf = StringBuffer();
    if (orderNo != null) buf.writeln('Order #$orderNo');
    if (status  != null) buf.writeln('Status: $status');
    if (rider   != null) buf.writeln('Delivery partner: $rider');
    if (eta     != null) buf.write('ETA: $eta');

    return buf.toString().trimRight().isEmpty ? fallback : buf.toString().trimRight();
  }

  static int? _parseBadge(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  // ── Tap routing ────────────────────────────────────────────────────────────

  // Called for both body tap and action button tap.
  static void _onTap(NotificationResponse response) {
    final route = (response.payload?.isNotEmpty == true)
        ? response.payload!
        : '/orders';
    _router?.push(route);
  }

  static void _handleFcmTap(RemoteMessage message) {
    final route = message.data['route'] as String?;
    if (route != null) _router?.push(route);
  }

  static Future<void> clearBadge() async {} // badge cleared via system on notification dismiss
}
