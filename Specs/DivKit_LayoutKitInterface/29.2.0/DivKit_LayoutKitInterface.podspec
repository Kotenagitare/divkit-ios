Pod::Spec.new do |s|
  s.name             = 'DivKit_LayoutKitInterface'
  s.module_name      = 'LayoutKitInterface'
  s.version          = '29.2.0'
  s.summary          = 'Part of DivKit framework'
  s.description      = 'Part of DivKit framework'
  s.homepage         = 'https://divkit.tech'

  s.license          = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author           = { 'divkit' => 'divkit@yandex-team.ru' }
  s.source           = { :git => 'https://github.com/divkit/divkit-ios.git', :tag => s.version.to_s }

  s.swift_version = '5.7'
  s.requires_arc = true
  s.prefix_header_file = false
  s.platforms = { :ios => '11.0' }

  s.dependency 'VGSLBase', '~> 2.4'
  s.dependency 'VGSLBaseTiny', '~> 2.4'
  s.dependency 'VGSLBaseUI', '~> 2.4'

  s.source_files = [
    'LayoutKit/Interface/**/*'
  ]
end
