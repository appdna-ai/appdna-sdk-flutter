Pod::Spec.new do |s|
  s.name             = 'appdna_sdk'
  s.version          = '0.3.0'
  s.summary          = 'AppDNA SDK Flutter plugin - iOS platform support.'
  s.description      = <<-DESC
Flutter plugin that bridges the AppDNA iOS SDK for analytics, experiments,
paywalls, surveys, web entitlements, and deferred deep links.
                       DESC
  s.homepage         = 'https://appdna.ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'AppDNA' => 'hello@appdna.ai' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'AppDNASDK', '~> 0.3.0'
  s.platform         = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
