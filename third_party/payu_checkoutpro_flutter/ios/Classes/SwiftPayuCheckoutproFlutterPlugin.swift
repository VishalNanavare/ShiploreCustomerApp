import Flutter
import UIKit
import PayUCheckoutProKit
import PayUCheckoutProBaseKit

public class SwiftPayuCheckoutproFlutterPlugin: NSObject, FlutterPlugin {
    
    enum MethodName: String {
        case openCheckoutScreen
        case hashGenerated
    }
    
    let ErrorDomain = "com.payu.PayUCheckoutProFlutter"
    let TopViewControllerUnavailable = "Top view controller not available"
    let InvalidMethodName = "Invalid method name"
    let genericErrorCode = 101
    
    let flutterMethodChannel:FlutterMethodChannel
    var responseTransformer: PayUHybridCheckoutProDelegateResponseTransformer?

    public init(channel:FlutterMethodChannel) {
        self.flutterMethodChannel = channel
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "CheckoutProChannel", binaryMessenger: registrar.messenger())
        let instance = SwiftPayuCheckoutproFlutterPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch (call.method) {
        case MethodName.openCheckoutScreen.rawValue:
            openCheckoutScreen(result: result, args: call.arguments)
        case MethodName.hashGenerated.rawValue:
            hashGenerated(result: result, args: call.arguments)
        default:
            onError(self.getErrorObjectFor(errmeMessage:InvalidMethodName,errorCode:genericErrorCode))
        }
    }
    
    private func hashGenerated(result: @escaping FlutterResult,args:Any?) {
        responseTransformer?.hashGenerated(args: args) { [weak self] error in
            if let error = error {
                self?.onError(error)
            }
        }
    }
    
    private func openCheckoutScreen(result: @escaping FlutterResult,args:Any?){
        guard let viewController = UIApplication.getTopViewController() else {
            onError(self.getErrorObjectFor(errmeMessage:TopViewControllerUnavailable,errorCode:genericErrorCode))
            return
        }
        responseTransformer = PayUHybridCheckoutProDelegateResponseTransformer()
        
        PayUCheckoutPro.open(on: viewController, params: args, delegate: self)
    }
    
    func getErrorObjectFor(errmeMessage:String,errorCode:Int) -> NSError {
        let errorObj = NSError(domain:ErrorDomain,
                               code:errorCode,
                               userInfo:[NSLocalizedDescriptionKey: NSLocalizedString("",value:errmeMessage, comment:"")])
        return errorObj
    }
    
}

extension SwiftPayuCheckoutproFlutterPlugin: PayUCheckoutProDelegate {
    public func onPaymentSuccess(response: Any?) {
        flutterMethodChannel.invokeMethod(PayUHybridCheckoutProDelegateResponseMethodName.onPaymentSuccess,
                                          arguments: responseTransformer?.onPaymentSuccess(response: response))
    }
    
    public func onPaymentFailure(response: Any?) {
        flutterMethodChannel.invokeMethod(PayUHybridCheckoutProDelegateResponseMethodName.onPaymentFailure,
                                          arguments: responseTransformer?.onPaymentFailure(response: response))
    }
    
    public func onPaymentCancel(isTxnInitiated: Bool) {
        flutterMethodChannel.invokeMethod(PayUHybridCheckoutProDelegateResponseMethodName.onPaymentCancel,
                                          arguments: responseTransformer?.onPaymentCancel(isTxnInitiated: isTxnInitiated))
    }
    
    public func onError(_ error: Error?) {
        flutterMethodChannel.invokeMethod(PayUHybridCheckoutProDelegateResponseMethodName.onError,
                                          arguments: responseTransformer?.onError(error))
    }
    
    public func generateHash(for param: DictOfString, onCompletion: @escaping PayUHashGenerationCompletion) {
        flutterMethodChannel.invokeMethod(PayUHybridCheckoutProDelegateResponseMethodName.generateHash,
                                          arguments: responseTransformer?.generateHash(for: param, onCompletion: onCompletion))
    }
}

extension UIApplication {
    
    class func getTopViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
            
        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
            
        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }
}