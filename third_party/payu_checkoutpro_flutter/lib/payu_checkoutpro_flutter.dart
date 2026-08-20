import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'dart:convert';


abstract class PayUCheckoutProProtocol {
  generateHash(Map response);
  onPaymentSuccess(dynamic response);
  onPaymentFailure(dynamic response);
  onPaymentCancel(Map? response);
  onError(Map? response);
}

class PayUCheckoutProFlutter {
  static const MethodChannel _channel = MethodChannel('CheckoutProChannel');
  PayUCheckoutProProtocol? delegate;

  PayUCheckoutProFlutter(PayUCheckoutProProtocol protocol) {
    delegate = protocol;
    _channel.setMethodCallHandler((call) async {
      if (call.method == "onPaymentSuccess") {
        delegate?.onPaymentSuccess(call.arguments);
      } else if (call.method == "onPaymentFailure") {
        delegate?.onPaymentFailure(call.arguments);
      } else if (call.method == "onPaymentCancel") {
        delegate?.onPaymentCancel(call.arguments);
      } else if (call.method == "onError") {
        delegate?.onError(call.arguments);
      } else if (call.method == "generateHash") {
        delegate?.generateHash(call.arguments);
      } else {
        delegate?.onPaymentFailure(call.arguments);
      }
    });
  }

   openCheckoutScreen(
      {required Map payUPaymentParams,
      required Map payUCheckoutProConfig}) async {
    try {
      var additionalParams = payUPaymentParams[Constants.additionalParam];
      additionalParams ??= {};
      additionalParams[Constants.analyticsData] = analyticsDict();
      payUPaymentParams[Constants.additionalParam] = additionalParams;

      final data = await _channel.invokeMethod('openCheckoutScreen', {
        Constants.payUPaymentParams: payUPaymentParams,
        Constants.payUCheckoutProConfig: payUCheckoutProConfig,
      });
      return data;
    } catch (error) {
      debugPrint(error.toString());
      final errorResponse = {Constants.errorCode:Constants.errorCodeValue, Constants.errorMsg:error.toString()};
      delegate?.onPaymentFailure(errorResponse);
    }
  }
  hashGenerated(
      {required Map<dynamic, dynamic>hash}) async {
    try {
      final data = await _channel
          .invokeMethod('hashGenerated', hash);
      return data;
    } catch (error) {
      debugPrint(error.toString()); 
      final errorResponse = {Constants.errorCode:Constants.errorCodeValue, Constants.errorMsg:error.toString()};
      delegate?.onPaymentFailure(errorResponse);
    }
  }

  String analyticsDict() {
 
    var platform = Platform.isAndroid ? "android":"iOS";
    var reactAnalyticsDict = {
        Constants.platform: platform,
        Constants.name: Constants.flutterCheckoutPro,
        Constants.version: "1.0.1", //TODO: Get Dynamic version from YAML. 
    };
    //TODO: Add this logic in wrapper for iOS or Android. 
    var reactAnalyticsArray = Platform.isAndroid ? reactAnalyticsDict:[reactAnalyticsDict];
    var reactAnalyticsStringyfied = json.encode(reactAnalyticsArray);
    return reactAnalyticsStringyfied;
 }
}


class Constants {
  static const payUPaymentParams = "payUPaymentParams";
  static const payUCheckoutProConfig = "payUCheckoutProConfig";
  static const errorCode = "errorCode";
  static const errorCodeValue = "1";
  static const errorMsg = "errorMsg";
  static const additionalParam = "additionalParam";
  static const flutterCheckoutPro = "Flutter_CheckoutPro";
  static const platform = "platform";
  static const name = "name";
  static const version = "version";
  static const analyticsData = "version";  

}
