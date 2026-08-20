import '../../core/network/api_client.dart';
import '../models/cart_item.dart';
import '../models/order.dart';

typedef CartValidation = ({bool valid, List<Map<String, dynamic>> issues, Totals totals, bool deliverableChecked, List<Map<String, dynamic>> lines});
typedef PlacedOrder = ({String orderNo, Totals totals, String paymentMethod});

class OrderRepository {
  OrderRepository(this._api);
  final ApiClient _api;

  List<Map<String, dynamic>> _itemsPayload(List<CartItem> items) =>
      items.map((e) => {'variant_id': e.variantId, 'qty': e.qty}).toList();

  Future<CartValidation> validateCart(List<CartItem> items, {double? lat, double? lng, String? coupon, String method = 'cod', double tip = 0}) async {
    final data = await _api.post('/customer/cart/validate', body: {
      'items': _itemsPayload(items),
      'lat': ?lat,
      'lng': ?lng,
      if ((coupon ?? '').isNotEmpty) 'coupon': coupon,
      'method': method,
      if (tip > 0) 'tip': tip,
    }) as Map;
    return (
      valid: data['valid'] == true,
      issues: ((data['issues'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
      totals: Totals.fromJson((data['totals'] as Map).cast<String, dynamic>()),
      deliverableChecked: data['deliverable_checked'] == true,
      lines: ((data['lines'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    );
  }

  /// Returns the discounted totals on success; throws ApiException (VALIDATION_ERROR) if invalid.
  Future<Totals> validateCoupon(String code, List<CartItem> items) async {
    final data = await _api.post('/customer/coupons/validate', body: {
      'code': code,
      'items': _itemsPayload(items),
    }) as Map;
    return Totals.fromJson((data['totals'] as Map).cast<String, dynamic>());
  }

  Future<PlacedOrder> placeOrder({
    required List<CartItem> items,
    required Map<String, dynamic> address,
    required double lat,
    required double lng,
    String method = 'cod',
    String? coupon,
    double tip = 0,
    String? gstin,
    String? deliveryInstructions,
    required String idempotencyKey,
  }) async {
    final data = await _api.post('/customer/orders', body: {
      'items': _itemsPayload(items),
      ...address,
      'lat': lat,
      'lng': lng,
      'method': method,
      if ((coupon ?? '').isNotEmpty) 'coupon': coupon,
      if (tip > 0) 'tip': tip,
      if ((gstin ?? '').isNotEmpty) 'gstin': gstin,
      if ((deliveryInstructions ?? '').isNotEmpty) 'delivery_instructions': deliveryInstructions,
      'idempotency_key': idempotencyKey,
    }) as Map;
    return (
      orderNo: (data['order_no'] ?? '').toString(),
      totals: data['totals'] is Map ? Totals.fromJson((data['totals'] as Map).cast<String, dynamic>()) : Totals.empty(),
      paymentMethod: (data['payment_method'] ?? method).toString(),
    );
  }

  /// Start an online (PayU) payment for a placed order. Returns the params the
  /// PayU CheckoutPro SDK needs (key, txnid, amount, hash, environment, …).
  Future<Map<String, dynamic>> payInit(String orderNo) async {
    final data = await _api.post('/customer/orders/$orderNo/pay') as Map;
    return data.cast<String, dynamic>();
  }

  /// Sign a PayU hash string for the SDK's generateHash callback (salt stays server-side).
  Future<String> payuHash(String hashString) async {
    final data = await _api.post('/customer/payu/hash', body: {'hash_string': hashString}) as Map;
    return (data['hash'] ?? '').toString();
  }

  /// Verify a PayU success response server-side; marks the order paid. Returns true when paid.
  Future<bool> payVerify(String orderNo, Map<String, dynamic> payuResponse) async {
    final data = await _api.post('/customer/orders/$orderNo/pay/verify', body: payuResponse) as Map;
    return (data['payment_status'] ?? '') == 'paid';
  }

  /// Active public coupons for the "see all coupons" sheet. Each: {code, pct, min_order_value}.
  Future<List<Map<String, dynamic>>> coupons() async {
    final res = await _api.getPage('/customer/coupons');
    return ((res.data as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<({List<OrderModel> items, int total, int pages})> orders({int page = 1}) async {
    final res = await _api.getPage('/customer/orders', query: {'page': '$page', 'per_page': '20'});
    final items = ((res.data as List?) ?? const [])
        .map((e) => OrderModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final meta = res.meta;
    return (
      items: items,
      total: (meta['total'] as num? ?? 0).toInt(),
      pages: (meta['pages'] as num? ?? 1).toInt(),
    );
  }

  Future<OrderModel> track(String orderNo) async {
    final data = await _api.get('/customer/track/$orderNo') as Map;
    return OrderModel.fromJson(data.cast<String, dynamic>());
  }

  Future<void> cancelOrder(String orderNo) =>
      _api.post('/customer/orders/$orderNo/cancel');

  Future<void> cancelItem(String orderNo, int subOrderId) =>
      _api.post('/customer/orders/$orderNo/cancel-item/$subOrderId');

  Future<void> returnItems(String orderNo, List<Map<String, dynamic>> items, String reason) =>
      _api.post('/customer/orders/$orderNo/return', body: {'items': items, 'reason': reason});

  Future<void> rateDelivery(int deliveryId, int rating, {String? comment}) =>
      _api.post('/customer/deliveries/$deliveryId/rate',
          body: {'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment});

  Future<List<int>> invoicePdfBytes(int subOrderId) =>
      _api.getBytes('/customer/sub-orders/$subOrderId/invoice/pdf');

  Future<dynamic> walletData() => _api.get('/customer/wallet');
}
