#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint payu_checkoutpro_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'payu_checkoutpro_flutter'
  s.version          = '1.2.0'
  s.summary          = 'Flutter plugin for PayU CheckoutPro SDK'
  s.description      = 'PayU CheckoutPro SDK can be used with this plugin.'
  s.homepage         = 'https://github.com/payu-intrepos/PayUCheckoutPro-Flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'PayU' => 'https://payu.in/'}
  s.source           = { :git => 'https://github.com/payu-intrepos/PayUCheckoutPro-Flutter.git', :tag => '#{s.version}'}
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'PayUIndia-CheckoutPro', '~>9.4'
  s.platform = :ios, '13.0'
end
