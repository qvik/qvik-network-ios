// The MIT License (MIT)
//
// Copyright (c) 2015-2016 Qvik (www.qvik.fi)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Alamofire
import SwiftKeychain

import QvikSwift

// Error domain for errors emitted by this class
let remoteServiceErrorDomain = "RemoteServiceErrorDomain"

// MARK: Util functions

/**
Returns a unique device identifier (UUID) that does not change for the same keychainServiceName
until the device is factory reset.

- parameter keychainServiceName: name for keychain entry for storing the device id, eg. "MyApp"
*/
public func getDeviceId(keychainServiceName: String) -> String {
    let key = GenericKey(keyName: "deviceId")
    let keychain = Keychain(serviceName: keychainServiceName, accessMode: kSecAttrAccessibleAlways, group: nil)
    
    if let deviceId = keychain.get(key).item?.value {
        log.verbose("deviceId found in keychain: \(deviceId)")
        return deviceId as String
    } else {
        let deviceId = NSUUID().UUIDString
        log.verbose("Created new deviceId: \(deviceId)")
        let deviceIdKey = GenericKey(keyName: "deviceId", value: deviceId)
        
        if let error = keychain.add(deviceIdKey) {
            log.error("Failed to add entry to keychain, error: \(error)")
            assert(false);
        }
        
        return deviceId
    }
}

/**
 Returns the client id string, which is of format:

 ```
 platform/manufacturer;deviceType;model;osversionmajor.osversionminor.osversionpatch/deviceId/languageCode
 ```

 - parameter keychainServiceName: name for keychain entry for storing the device id, eg. "MyApp"
 */
public func getClientId(keychainServiceName: String) -> String {
    let key = "hw.machine".cStringUsingEncoding(NSUTF8StringEncoding)
    var size: Int = 0
    sysctlbyname(key!, nil, &size, nil, 0)
    var machine = [CChar](count: Int(size), repeatedValue: 0)
    sysctlbyname(key!, &machine, &size, nil, 0)
    let model = String.fromCString(machine)!
    
    let deviceType = UIDevice.currentDevice().model
    let osVersion = NSProcessInfo.processInfo().operatingSystemVersion
    let deviceId = getDeviceId(keychainServiceName)
    
    let clientId = String(format: "IOS/Apple;%@;%@;%d.%d.%d/%@/%@", deviceType, model, osVersion.majorVersion,
        osVersion.minorVersion, osVersion.patchVersion, deviceId, NSLocale.preferredLanguages().first!)
    
    log.verbose("Using clientId = \(clientId)")
    
    return clientId
}

// MARK: BaseRemoteService

/**
Base class for Remote API communications, providing Alamofire wrappers and response handling.

Example implementation:

```swift
class RemoteService: BaseRemoteService {
  private static let singletonInstance = RemoteService()

  class func sharedInstance() -> RemoteService {
    return singletonInstance
  }

  /// Attempts to verify an email address
  func verifyEmailAddress(email: String, completionCallback: (RemoteResponse -> Void)) {
    let url = "\(baseUrl)/api/verifyemail"
    let params = ["email": email]

    request(.POST, url, parameters: params, encoding: .JSON, headers: nil) { response in
      completionCallback(response)
    }
  }

  // TODO Other methods ..

  init() {
    let additionalHeaders = [
      "X-My-API-Key": "asldasdaksdjhakdjhasdkjh",
      "X-My-Api-Version": "1",
      "X-My-Client": getClientId(keychainServiceName: "ServicName")
    ]

    super.init(backgroundSessionId: "com.example.MyApp", additionalHeaders: additionalHeaders, timeout: 5)
  }
}
```

*/
public class BaseRemoteService {
    /// Alamofire facade
    private let manager: Alamofire.Manager
    
    public typealias AuthenticationMapping = (headerName: String, authToken: String)
    
    /**
     Returns either a valid JSON response or an error.
    */
    private func createRemoteResponse(afResponse: Response<AnyObject, NSError>) -> RemoteResponse {
        // First handle network errors
        if let error = afResponse.result.error {
            let remoteError = (error.code == NSURLErrorTimedOut) ? RemoteResponse.RemoteError.NetworkTimeout : RemoteResponse.RemoteError.NetworkError
            return RemoteResponse(nsError: error, remoteError: remoteError, json: nil)
        }

        let jsonResponse = afResponse.result.value 
        let statusCode = afResponse.response?.statusCode
        log.verbose("HTTP Status code: \(statusCode)")
        
        if let code = statusCode where code < 200 || code >= 300 {
            log.debug("Got non-success HTTP response: \(code)")
            
            var remoteError = RemoteResponse.RemoteError.ServerError
            
            switch code {
            case 401:
                remoteError = .BadCredentials
            case 404:
                remoteError = .NotFound
            default:
                remoteError = .ServerError
            }

            let nsError = NSError(domain: remoteServiceErrorDomain, code: code, userInfo: nil)
            let remoteResponse = RemoteResponse(nsError: nsError, remoteError: remoteError, json: jsonResponse)
            
            return remoteResponse
        }
        
        if let jsonResponse = jsonResponse {
            log.verbose("Received a valid response.")
            return RemoteResponse(json: jsonResponse)
        } else {
            log.debug("Received invalid or empty JSON response: \(afResponse.result.value)")
            return RemoteResponse()
        }
    }
    
    /**
    Makes a REST request against the given URL and expects a JSON response.
    
    - parameter method: HTTP method
    - parameter URLString: Request URL
    - parameter parameters: Request parameters
    - parameter encoding: Request encoding
    - parameter headers: Any extra headers
    */
    public func request(method: Alamofire.Method, _ URLString: URLStringConvertible, parameters: [String : AnyObject]?, encoding: ParameterEncoding = .URL, headers: [String: String]? = nil, callback: ((RemoteResponse) -> Void)) {
        
        log.verbose("Making a request to url: \(URLString)")
        
        let (request, error) = encoding.encode(NSMutableURLRequest(URL: NSURL(string: URLString.URLString)!), parameters: parameters)
        if let error = error {
            log.error("Failed to encode request, error: \(error)")
            assert(false)
        }
        
        request.HTTPMethod = method.rawValue
        
        if let headers = headers {
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        
        if let authMapping = getAuthentication() {
            log.verbose("Using access token: \(authMapping.authToken)")
            request.setValue(authMapping.authToken, forHTTPHeaderField: authMapping.headerName)
        }
        
        manager.request(request).responseJSON { response in
            log.verbose("Request completed, URL: \(response.request?.URL), response: \(response), status code = \(response.response?.statusCode)")
            callback(self.createRemoteResponse(response))
        }
    }
    
    /**
    If the implementation uses header based access token authentication, it must implement this 
    method to provide the access token (and related HTTP header name) when applicable.
    
    Example implementation: 
    
    ```swift
    override func getAuthentication() -> AuthenticationMapping? {
      if let accessToken = appstate.accessToken {
        return ("X-My-Auth-Token", accessToken)
      } else {
        return nil
      }
    }
    ```
    */
    public func getAuthentication() -> AuthenticationMapping? {
        // Base implementation does not nothing
        return nil
    }
    
    /**
    Initializes the base class.
    
    - parameter backgroundSessionId: background session id; eg. com.example.myapp.remote
    - parameter additionalHeaders: optional map of additional (custom) HTTP headers
    - parameter timeout: HTTP response timeout in seconds
    */
    public init(backgroundSessionId: String, additionalHeaders: [String: AnyObject]? = nil, timeout: NSTimeInterval = 10) {
        // Set up AlamoFire instance
        var defaultHeaders = Alamofire.Manager.sharedInstance.session.configuration.HTTPAdditionalHeaders ?? [:]
        if let additionalHeaders = additionalHeaders {
            for (key, value) in additionalHeaders {
                defaultHeaders[key] = value
            }
        }
        
        let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier(backgroundSessionId)
        configuration.HTTPAdditionalHeaders = defaultHeaders
        configuration.timeoutIntervalForResource = timeout
        log.verbose("Using default headers: \(defaultHeaders)");
        
        manager = Alamofire.Manager(configuration: configuration)
    }
}
