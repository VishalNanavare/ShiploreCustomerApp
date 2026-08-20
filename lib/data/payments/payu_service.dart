import 'dart:async';
import 'dart:convert';

import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';

import '../../../core/config/app_config.dart';

enum PayUOutcome { success, failure, cancelled }

typedef PayUResult = ({PayUOutcome outcome, Map<String, dynamic> response});

/// Signs a PayU hash string server-side (the merchant salt never leaves the
/// backend). Wired to [OrderRepository.payuHash].
typedef HashSigner = Future<String> Function(String hashString);

/// Thin wrapper over `payu_checkoutpro_flutter`. Opens the PayU CheckoutPro
/// screen for a placed order and resolves a [PayUResult] when the user finishes,
/// fails, or cancels. Every hash the SDK requests is signed by the backend.
class PayUService implements PayUCheckoutProProtocol {
  PayUService({required this.signHash});
  final HashSigner signHash;

  late final PayUCheckoutProFlutter _payu = PayUCheckoutProFlutter(this);
  Completer<PayUResult>? _completer;

  /// Opens the checkout screen. [paymentParams] is the map returned by
  /// `OrderRepository.payInit` (key, txnid, amount, productinfo, firstname,
  /// email, phone, hash, environment).
  Future<PayUResult> pay({
    required Map<String, dynamic> init,
    String successUrl = AppConfig.payuSuccessUrl,
    String failureUrl = AppConfig.payuFailureUrl,
  }) {
    _completer = Completer<PayUResult>();
    final params = <String, dynamic>{
      PayUPaymentParamKey.key: '${init['key'] ?? ''}',
      PayUPaymentParamKey.amount: '${init['amount'] ?? ''}',
      PayUPaymentParamKey.productInfo: '${init['productinfo'] ?? 'Order'}',
      PayUPaymentParamKey.firstName: '${init['firstname'] ?? 'Customer'}',
      PayUPaymentParamKey.email: '${init['email'] ?? ''}',
      PayUPaymentParamKey.phone: '${init['phone'] ?? ''}',
      PayUPaymentParamKey.transactionId: '${init['txnid'] ?? ''}',
      PayUPaymentParamKey.environment: '${init['environment'] ?? 1}',
      PayUPaymentParamKey.android_surl: successUrl,
      PayUPaymentParamKey.android_furl: failureUrl,
      PayUPaymentParamKey.ios_surl: successUrl,
      PayUPaymentParamKey.ios_furl: failureUrl,
    };
    _payu.openCheckoutScreen(
      payUPaymentParams: params,
      payUCheckoutProConfig: {},
    );
    return _completer!.future;
  }

  // ---- PayUCheckoutProProtocol ----

  @override
  generateHash(Map response) async {
    final name = response[PayUHashConstantsKeys.hashName];
    final str = response[PayUHashConstantsKeys.hashString];
    if (name == null || str == null) return;
    try {
      final signed = await signHash(str.toString());
      _payu.hashGenerated(hash: {name: signed});
    } catch (_) {
      _finish(PayUOutcome.failure, {'errorMsg': 'Hash generation failed'});
    }
  }

  @override
  onPaymentSuccess(dynamic response) => _finish(PayUOutcome.success, response);

  @override
  onPaymentFailure(dynamic response) => _finish(PayUOutcome.failure, response);

  @override
  onPaymentCancel(Map? response) =>
      _finish(PayUOutcome.cancelled, response ?? const {});

  @override
  onError(Map? response) => _finish(PayUOutcome.failure, response ?? const {});

  void _finish(PayUOutcome outcome, dynamic response) {
    if (_completer == null || _completer!.isCompleted) return;
    _completer!.complete((outcome: outcome, response: _normalize(response)));
  }

  /// PayU returns the gateway fields under `payuResponse` (a JSON string on
  /// success). Flatten it so the backend can verify the reverse hash.
  Map<String, dynamic> _normalize(dynamic response) {
    if (response is! Map) return {'raw': '$response'};
    final out = <String, dynamic>{};
    response.forEach((k, v) => out['$k'] = v);
    final raw = out['payuResponse'] ?? out['merchantResponse'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) decoded.forEach((k, v) => out['$k'] = v);
      } catch (_) {}
    }
    return out;
  }
}
