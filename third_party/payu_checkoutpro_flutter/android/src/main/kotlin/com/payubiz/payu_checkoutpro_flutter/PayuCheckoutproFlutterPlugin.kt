package com.payubiz.payu_checkoutpro_flutter

import android.app.Activity
import android.os.Looper
import android.webkit.WebView
import androidx.annotation.NonNull
import com.payu.base.models.ErrorResponse
import com.payu.checkoutpro.PayUCheckoutPro
import com.payu.checkoutpro.parser.CheckoutProCallbackToJSONParser
import com.payu.checkoutpro.parser.constants.PayUHybridKeys
import com.payu.checkoutpro.parser.constants.PayUHybridValues
import com.payu.ui.model.listeners.PayUCheckoutProListener
import com.payu.ui.model.listeners.PayUHashGenerationListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** PayuCheckoutproFlutterPlugin */
class PayuCheckoutproFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var responseTransformer: CheckoutProCallbackToJSONParser? = null
    private val INVALID_MERCHANT_REQUEST_PARMS = "Invalid payment request parameter"
    private val INVALID_METHOD_NAME = "Invalid method name"

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "CheckoutProChannel")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method.equals("openCheckoutScreen")) {
            val arguments = call.arguments as? HashMap<String, Any>
            if (arguments != null){
                openCheckoutScreen(arguments)
            }else {
                val errorResponse = ErrorResponse()
                errorResponse.errorMessage  = INVALID_MERCHANT_REQUEST_PARMS
                errorResponse.errorCode = PayUHybridValues.Error.GENERIC_ERROR_CODE
                onErrorCallback(errorResponse)
            }
        } else if (call.method.equals("hashGenerated")) {
            hashGenerated(call.arguments)
        } else {
            val errorResponse = ErrorResponse()
            errorResponse.errorMessage  = INVALID_METHOD_NAME
            errorResponse.errorCode = PayUHybridValues.Error.GENERIC_ERROR_CODE
            onErrorCallback(errorResponse)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {

    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {

    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun sendResultBack(result: Any?, methodName: String) {
        val action = {
            try {
                channel.invokeMethod(methodName, result)
            } catch (e: Exception) {
                val errorResponse = ErrorResponse()
                errorResponse.errorMessage  = INVALID_METHOD_NAME
                errorResponse.errorCode = PayUHybridValues.Error.GENERIC_ERROR_CODE
                onErrorCallback(errorResponse)            }
        }
        if(Looper.myLooper() == Looper.getMainLooper()){
            action.invoke()
        } else {
            if (activity != null && !activity?.isFinishing!! && !activity?.isDestroyed!!) {
                activity!!.runOnUiThread {
                    action.invoke()
                }
            }
        }

    }

    private fun hashGenerated(params: Any?) {
        responseTransformer?.hashGenerated(activity, params){
            if (it != null) {
                onErrorCallback(it)
            }
        }
    }

    private fun openCheckoutScreen(params: HashMap<String, Any>) {
        responseTransformer = CheckoutProCallbackToJSONParser()

        if (activity != null && !activity?.isFinishing!! && !activity?.isDestroyed!!) {
            with(PayUCheckoutPro) {
                open(activity!!, params,object:
                    PayUCheckoutProListener {
                        override fun onPaymentSuccess(response: Any) {
                            sendResultBack(responseTransformer?.onPaymentSuccess(response), PayUHybridKeys.Others.onPaymentSuccess)
                        }

                        override fun onPaymentFailure(response: Any) {
                            sendResultBack(responseTransformer?.onPaymentFailure(response), PayUHybridKeys.Others.onPaymentFailure)
                        }

                        override fun onPaymentCancel(isTxnInitiated: Boolean) {
                            sendResultBack(responseTransformer?.onPaymentCancel(isTxnInitiated), PayUHybridKeys.Others.onPaymentCancel)
                        }

                        override fun onError(errorResponse: ErrorResponse) {
                            onErrorCallback(errorResponse)
                        }

                        override fun setWebViewProperties(webView: WebView?, bank: Any?) {
                        }

                        override fun generateHash(
                            map: HashMap<String, String?>,
                            hashListener: PayUHashGenerationListener
                        ) {
                            sendResultBack(responseTransformer?.generateHash(map, hashListener), PayUHybridKeys.Others.generateHash)
                        }
                    }
                )
            }
        }
        else {
            val errorResponse = ErrorResponse()
            errorResponse.errorMessage  = PayUHybridValues.Error.ACTIVITY_OR_CONTEXT_NULL
            errorResponse.errorCode = PayUHybridValues.Error.GENERIC_ERROR_CODE
            onErrorCallback(errorResponse)
        }
    }

    private fun onErrorCallback(errorResponse: ErrorResponse) {
        sendResultBack(responseTransformer?.onError(errorResponse), PayUHybridKeys.Others.onError)
    }
}



