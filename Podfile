platform :ios, '9.0'
use_frameworks!

source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/qvik/qvik-podspecs.git'

def all_pods
  pod 'Alamofire', '~> 4.0'
  pod 'QvikSwift', '~> 4'
  #pod 'QvikSwift', :path => '../qvik-swift-ios/'
  pod 'QvikUi', '~> 4'
  #pod 'QvikUi', :path => '../qvik-ui-ios/'
  pod 'XCGLogger', '~> 6.0'
  pod 'CryptoSwift', '~> 0.7'
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
            config.build_settings['SWIFT_VERSION'] = '4.0'
        end
    end
end
