platform :ios, '9.0'
use_frameworks!

source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/qvik/qvik-podspecs.git'

def pods
  pod 'Alamofire', '~> 4.0'
  #  pod 'QvikSwift', '~> 3.0'
  pod 'QvikSwift', :path => '../qvik-swift-ios/'
  pod 'XCGLogger', '~> 4.0'
  pod 'CryptoSwift', '~> 0.6'
end

target 'QvikNetwork' do
  pods
end

target 'QvikNetworkTests' do
  pods
end
