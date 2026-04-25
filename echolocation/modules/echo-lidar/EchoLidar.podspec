require 'json'

absolute_react_native_path = ''
if !ENV['REACT_NATIVE_PATH'].nil?
  absolute_react_native_path = File.expand_path(ENV['REACT_NATIVE_PATH'], Pod::Config.instance.project_root)
else
  absolute_react_native_path = File.dirname(`node --print "require.resolve('react-native/package.json')"`)
end

unless defined?(install_modules_dependencies)
  require File.join(absolute_react_native_path, 'scripts/react_native_pods')
end

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'EchoLidar'
  s.version        = package['version']
  s.summary        = 'Local Expo module for LiDAR depth support in the Echolocation app.'
  s.description    = s.summary
  s.license        = 'MIT'
  s.author         = 'Echolocation Team'
  s.homepage       = 'https://expo.dev'
  s.platforms      = {
    :ios => '15.1'
  }
  s.swift_version  = '5.4'
  s.source         = { git: 'https://github.com/expo/expo.git' }
  s.static_framework = true

  s.source_files = 'ios/**/*.{swift,h,m,mm}'

  s.dependency 'ExpoModulesCore'
  # LiteRT-LM (Google AI Edge) — for Gemma 4 E2B on-device inference.
  # Once you adopt the production backend, uncomment + run `pod install`.
  # s.dependency 'TensorFlowLiteSwift/CoreML', '~> 2.17'
  install_modules_dependencies(s)
end
