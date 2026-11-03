# The Hailbell Flutter plugin for apps that still use CocoaPods.
# hailbell/Sources/hailbell/Vendor is the native Swift SDK, copied from sdk/swift by tool/sync_native.sh.
Pod::Spec.new do |s|
  s.name             = 'hailbell'
  s.version          = '0.1.0'
  s.summary          = 'In-app support chat and push notifications from Hailbell.'
  s.description      = <<-DESC
The Hailbell chat screen and push notifications for Flutter apps, using Hailbell's native Swift SDK.
                       DESC
  s.homepage         = 'https://hailbell.com'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Hailbell' => 'hello@hailbell.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'hailbell/Sources/hailbell/**/*.swift'
  s.resource_bundles = { 'hailbell_privacy' => ['hailbell/Sources/hailbell/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform         = :ios, '16.0'
  s.frameworks       = 'UIKit', 'SwiftUI', 'UserNotifications', 'PhotosUI', 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.9'
end
