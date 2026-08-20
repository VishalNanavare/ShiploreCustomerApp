import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String, !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    // Required for firebase_messaging to show foreground notifications on iOS.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Expose native config values to Dart so Flutter can read keys that live in
    // Info.plist (or Build Settings) without requiring a --dart-define at build time.
    let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String ?? ""
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "com.shiplore.config") {
      FlutterMethodChannel(name: "com.shiplore/config", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          switch call.method {
          case "getMapsApiKey":
            result(mapsKey)
          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
