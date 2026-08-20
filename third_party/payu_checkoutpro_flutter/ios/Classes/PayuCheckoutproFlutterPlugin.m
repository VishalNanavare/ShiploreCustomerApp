#import "PayuCheckoutproFlutterPlugin.h"
#if __has_include(<payu_checkoutpro_flutter/payu_checkoutpro_flutter-Swift.h>)
#import <payu_checkoutpro_flutter/payu_checkoutpro_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "payu_checkoutpro_flutter-Swift.h"
#endif

@implementation PayuCheckoutproFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftPayuCheckoutproFlutterPlugin registerWithRegistrar:registrar];
}
@end
