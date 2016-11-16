platform :ios, '8.0'
use_frameworks!

source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/qvik/qvik-podspecs.git'

def pods
  pod 'Alamofire', '~> 3.0'
  pod 'QvikSwift', '~> 2.0.0'
#  pod 'QvikSwift', :path => '../qvik-swift-ios/'
  pod 'XCGLogger', '~> 3.0'
  pod 'CryptoSwift', '~> 0.5.1'
  pod 'SwiftKeychain', '~> 0.1'
  pod 'SwiftGifOrigin', '~> 1.5.0'
end

target 'QvikNetwork' do
  pods
end

target 'QvikNetworkTests' do
  pods
end
