Pod::Spec.new do |s|
  s.name             = 'linksense'
  s.version          = '0.2.0'
  s.summary          = 'Flutter plugin for LinkSense dynamic links and deferred deep linking.'
  s.description      = <<-DESC
Thin MethodChannel bridge over the native LinkSense iOS SDK. Handles SDK
configure / start, deferred-deep-link streaming, link CRUD and Universal
Link observation; all attribution logic lives in the native SDK, which is
vendored into this pod (linksense/Sources/linksense/LinkSenseCore/, synced by
sync-ios-sdk.sh at a pinned tag). SwiftPM hosts build the same sources from
linksense/Package.swift.
                       DESC
  s.homepage         = 'https://linksense.net'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'LinkSense' => 'support@linksense.net' }
  s.source           = { :git => 'https://github.com/LinkSense-net/linksense-flutter.git', :tag => "v#{s.version}" }
  s.source_files     = 'linksense/Sources/linksense/**/*.swift'
  s.resource_bundles = {
    'linksense_privacy' => ['linksense/Sources/linksense/Resources/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.platform         = :ios, '16.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.9'
end
