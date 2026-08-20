import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A single customer notification (order update, delivery alert, offer, …).
class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.eventCode,
    this.createdAt,
    this.readAt,
    this.data = const {},
  });

  final int id;
  final String title;
  final String body;
  final String eventCode;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;

  bool get isRead => readAt != null;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: int.tryParse(j['id'].toString()) ?? 0,
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        eventCode: (j['event_code'] ?? '').toString(),
        createdAt: DateTime.tryParse('${j['created_at']}'),
        readAt: DateTime.tryParse('${j['read_at']}'),
        data: _parseData(j['data']),
      );

  static Map<String, dynamic> _parseData(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    return {};
  }
}

/// Category of a notification — derived from its `event_code`. Centralises the
/// icon / colour / background styling shared by the notifications screen.
enum NotificationCategory {
  order(Icons.receipt_long_rounded, AppColors.cta, AppColors.ctaTint),
  delivery(Icons.local_shipping_rounded, AppColors.teal, Color(0xFFE1F7FA)),
  payment(Icons.payment_rounded, AppColors.success, Color(0xFFE6F6EF)),
  refund(Icons.assignment_return_rounded, AppColors.info, Color(0xFFEEF4FF)),
  promo(Icons.local_offer_rounded, AppColors.accent, Color(0xFFFFF8E1)),
  other(Icons.campaign_rounded, AppColors.inkSoft, AppColors.bgTint);

  const NotificationCategory(this.icon, this.color, this.bg);

  final IconData icon;
  final Color color;
  final Color bg;

  static NotificationCategory fromCode(String eventCode) {
    final c = eventCode.toLowerCase();
    if (c.contains('deliver')) return NotificationCategory.delivery;
    if (c.contains('return') || c.contains('refund')) return NotificationCategory.refund;
    if (c.contains('payment')) return NotificationCategory.payment;
    if (c.contains('promo') || c.contains('offer')) return NotificationCategory.promo;
    if (c.contains('order')) return NotificationCategory.order;
    return NotificationCategory.other;
  }
}
