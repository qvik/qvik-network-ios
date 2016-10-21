platform :ios, '9.0'
use_frameworks!

source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/qvik/qvik-podspecs.git'

def all_pods
  pod 'Alamofire', '~> 4.0'
  pod 'QvikSwift', '~> 3'
  #pod 'QvikSwift', :path => '../qvik-swift-ios/'
  pod 'QvikUi', '~> 1'
  #pod 'QvikUi', :path => '../qvik-ui-ios/'
  pod 'XCGLogger', '~> 4.0'
  pod 'CryptoSwift', '~> 0.6'
end

target 'QvikNetwork' do
  all_pods
end

target 'QvikNetworkTests' do
  all_pods
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '3.0'
        end
    end
end
