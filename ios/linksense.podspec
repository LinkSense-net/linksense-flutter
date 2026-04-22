Pod::Spec.new do |s|
  s.name             = 'linksense'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for LinkSense dynamic links and deferred deep linking.'
  s.description      = <<-DESC
Thin MethodChannel bridge over the native LinkSense iOS SDK. Handles
SDK configure / start, deferred-deep-link streaming, and link CRUD —
all attribution logic lives in the native pod.
                       DESC
  s.homepage         = 'https://linksense.net'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'LinkSense' => 'support@linksense.net' }
  s.source           = { :git => 'https://github.com/jankokalj/linksense-flutter.git', :tag => s.version.to_s }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # Pull the native iOS SDK via its CocoaPods spec. When the SDK is
  # published as a private pod, update the URL / version below or swap
  # for a `:podspec =>` reference.
  # s.dependency 'LinkSense', '~> 0.1.0'
  s.platform         = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
