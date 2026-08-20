import 'dart:convert';

import '../../core/utils/formatx.dart';

/// Server-computed cart/order totals (cart/validate, coupons/validate, placeOrder).
class Totals {
  Totals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.delivery,
    required this.grand,
    required this.count,
    this.handling = 0,
    this.tip = 0,
    this.savings = 0,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double delivery;
  final double handling;
  final double tip;
  final double savings; // MRP savings on items (Σ (mrp-price)*qty)
  final double grand;
  final int count;

  /// Everything the customer saved on this order vs. MRP + coupon.
  double get totalSavings => savings + discount;

  factory Totals.fromJson(Map<String, dynamic> j) => Totals(
        subtotal: Formatx.toDouble(j['subtotal']),
        discount: Formatx.toDouble(j['discount']),
        tax: Formatx.toDouble(j['tax']),
        delivery: Formatx.toDouble(j['delivery']),
        handling: Formatx.toDouble(j['handling']),
        tip: Formatx.toDouble(j['tip']),
        savings: Formatx.toDouble(j['savings']),
        grand: Formatx.toDouble(j['grand']),
        count: Formatx.toInt(j['count']),
      );

  static Totals empty() => Totals(subtotal: 0, discount: 0, tax: 0, delivery: 0, grand: 0, count: 0);
}

/// An order item line within a sub-order (track).
class OrderItem {
  OrderItem({required this.orderItemId, required this.title, this.sku, required this.qty, required this.unitPrice, this.status});

  final int orderItemId;
  final String title;
  final String? sku;
  final double qty;
  final double unitPrice;
  final String? status;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        orderItemId: Formatx.toInt(j['order_item_id']),
        title: (j['product_title_snapshot'] ?? '').toString(),
        sku: j['sku_snapshot']?.toString(),
        qty: Formatx.toDouble(j['qty']),
        unitPrice: Formatx.toDouble(j['unit_price']),
        status: j['status']?.toString(),
      );
}

/// Live delivery + assigned rider for a sub-order.
class DeliveryInfo {
  DeliveryInfo({this.id, this.status, this.riderName, this.riderPhone, this.riderLat, this.riderLng, this.eta});

  final int? id;
  final String? status;
  final String? riderName;
  final String? riderPhone;
  final double? riderLat;
  final double? riderLng;
  final String? eta;

  bool get hasRider => (riderName ?? '').isNotEmpty;

  factory DeliveryInfo.fromJson(Map<String, dynamic> j) => DeliveryInfo(
        id: j['id'] == null ? null : int.tryParse(j['id'].toString()),
        status: j['delivery_status']?.toString(),
        riderName: j['rider_name']?.toString(),
        riderPhone: j['rider_phone']?.toString(),
        riderLat: j['rider_lat'] == null ? null : Formatx.toDouble(j['rider_lat']),
        riderLng: j['rider_lng'] == null ? null : Formatx.toDouble(j['rider_lng']),
        eta: j['eta_at']?.toString(),
      );
}

/// One per-product bill (sub-order) within an order.
class SubOrder {
  SubOrder({
    required this.subOrderId,
    required this.subOrderNo,
    required this.status,
    required this.grandTotal,
    this.vendor,
    this.items = const [],
    this.delivery,
    this.deliveryOtp,
    this.invoiceId,
  });

  final int subOrderId;
  final String subOrderNo;
  final String status;
  final double grandTotal;
  final String? vendor;
  final List<OrderItem> items;
  final DeliveryInfo? delivery;
  final String? deliveryOtp;
  final int? invoiceId;

  factory SubOrder.fromJson(Map<String, dynamic> j) => SubOrder(
        subOrderId: Formatx.toInt(j['sub_order_id']),
        subOrderNo: (j['sub_order_no'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        grandTotal: Formatx.toDouble(j['grand_total']),
        vendor: j['vendor']?.toString(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => OrderItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        delivery: j['delivery'] is Map ? DeliveryInfo.fromJson((j['delivery'] as Map).cast<String, dynamic>()) : null,
        deliveryOtp: j['delivery_otp']?.toString(),
        invoiceId: j['invoice_id'] is int ? j['invoice_id'] as int : null,
      );
}

/// Order summary (list) + full track detail.
class ReturnItem {
  ReturnItem({required this.title, required this.qty, required this.refundAmount, this.sku});
  final String title;
  final double qty;
  final double refundAmount;
  final String? sku;

  factory ReturnItem.fromJson(Map<String, dynamic> j) => ReturnItem(
        title: (j['title'] ?? 'Item').toString(),
        qty: Formatx.toDouble(j['qty']),
        refundAmount: Formatx.toDouble(j['refund_amount']),
        sku: j['sku']?.toString(),
      );
}

class ReturnRequest {
  ReturnRequest({required this.uuid, required this.status, required this.createdAt, this.customerNote, this.items = const []});
  final String uuid;
  final String status; // requested | approved | refunded | rejected
  final String createdAt;
  final String? customerNote;
  final List<ReturnItem> items;

  double get totalRefund => items.fold(0, (s, i) => s + i.refundAmount);

  factory ReturnRequest.fromJson(Map<String, dynamic> j) => ReturnRequest(
        uuid: (j['uuid'] ?? '').toString(),
        status: (j['status'] ?? 'requested').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        customerNote: j['customer_note']?.toString(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => ReturnItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class OrderModel {
  OrderModel({
    required this.orderNo,
    required this.status,
    required this.grandTotal,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.deliveryTotal = 0,
    this.handlingTotal = 0,
    this.tipTotal = 0,
    this.discountTotal = 0,
    this.placedAt,
    this.paymentStatus,
    this.billingAddress = const {},
    this.subOrders = const [],
    this.returns = const [],
  });

  final String orderNo;
  final String status;
  final double grandTotal;
  final double subtotal;
  final double taxTotal;
  final double deliveryTotal;
  final double handlingTotal;
  final double tipTotal;
  final double discountTotal;
  final String? placedAt;
  final String? paymentStatus;
  final Map<String, dynamic> billingAddress;
  final List<SubOrder> subOrders;
  final List<ReturnRequest> returns;

  static Map<String, dynamic> _parseAddress(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try { return (jsonDecode(raw) as Map).cast<String, dynamic>(); } catch (_) {}
    }
    return {};
  }

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
        orderNo: (j['order_no'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        grandTotal: Formatx.toDouble(j['grand_total']),
        subtotal: Formatx.toDouble(j['subtotal']),
        taxTotal: Formatx.toDouble(j['tax_total']),
        deliveryTotal: Formatx.toDouble(j['delivery_total']),
        handlingTotal: Formatx.toDouble(j['handling_total']),
        tipTotal: Formatx.toDouble(j['tip_total']),
        discountTotal: Formatx.toDouble(j['discount_total']),
        placedAt: (j['placed_at'] ?? j['created_at'])?.toString(),
        paymentStatus: j['payment_status']?.toString(),
        billingAddress: _parseAddress(j['billing_address_json']),
        subOrders: ((j['sub_orders'] as List?) ?? const [])
            .map((e) => SubOrder.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        returns: ((j['returns'] as List?) ?? const [])
            .map((e) => ReturnRequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
