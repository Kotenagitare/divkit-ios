Pod::Spec.new do |s|
  s.name             = 'DivKitExtensions'
  s.version          = '28.13.0-source'
  s.summary          = 'DivKit framework extensions'
  s.description      = 'Part of DivKit framework'
  s.homepage         = 'https://divkit.tech'

  s.license          = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author           = { 'divkit' => 'divkit@yandex-team.ru' }
  s.source           = { :git => 'https://github.com/Kotenagitare/divkit-ios.git', :tag => s.version.to_s }

  s.swift_version = '5.7'
  s.requires_arc = true
  s.prefix_header_file = false
  s.platforms = { :ios => '11.0' }

  s.dependency 'DivKit', s.version.to_s

  s.source_files = [
    'DivKitExtensions/**/*'
  ]
end
