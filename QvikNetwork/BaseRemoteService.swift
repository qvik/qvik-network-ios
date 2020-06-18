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
import QvikSwift

// Error domain for errors emitted by this class
let remoteServiceErrorDomain = "RemoteServiceErrorDomain"

// MARK: Util functions

/**
 Returns a unique device identifier (UUID) that does not change for the same keychainServiceName
 until the device is factory reset.

 - parameter keychainServiceName: name for keychain entry for storing the device id, eg. "MyApp"
 - throws: May throw an exception if keychain access fails
 */
public func getDeviceId(_ keychainServiceName: String) throws -> String {
    let keyName = "deviceId"
    let keychain = Keychain(serviceName: keychainServiceName, accessMode: kSecAttrAccessibleAlways as String)

    if let deviceId = try keychain.getValue(key: keyName) {
        log.verbose("deviceId found in keychain: \(deviceId)")

        return deviceId
    } else {
        let deviceId = UUID().uuidString
        log.verbose("Created new deviceId: \(deviceId)")
        try keychain.addValue(key: keyName, value: deviceId)

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
public func getClientId(_ keychainServiceName: String) -> String {
    let key = "hw.machine".cString(using: String.Encoding.utf8)
    var size: Int = 0
    sysctlbyname(key!, nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: Int(size))
    sysctlbyname(key!, &machine, &size, nil, 0)
    let model = String(cString: machine)
    
    let deviceType = UIDevice.current.model
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    var deviceId = ""

    do {
        deviceId = try getDeviceId(keychainServiceName)
    } catch {
        log.error("Caught an error while getting devviceId: \(error)")
    }

    let clientId = String(format: "IOS/Apple;%@;%@;%d.%d.%d/%@/%@", deviceType, model, osVersion.majorVersion,
        osVersion.minorVersion, osVersion.patchVersion, deviceId, Locale.preferredLanguages.first!)
    
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

 Also notice that despite the class name, ```BaseRemoteService``` can as well be used with a ```has-a```
 relationship instead of a ```is-a``` relationship; this is especially useful for mocking. Here's an example of has-a use:
 
 ```swift
 class RemoteService {
   let remoteImpl: BaseRemoteService
   let baseUrl = "http://www.site.com"

   // .. methods ..

   init(remoteImpl: BaseRemoteService) {
     self.remoteImpl = remoteImpl
   }
 }
 ```
*/
open class BaseRemoteService {
    /// Alamofire facade
    fileprivate let manager: Session

    /// Defines the mechanism for wrapping a single header name to a (auth) token value.
    public typealias AuthenticationMapping = (headerName: String, authToken: String)

    /// If enabled, prints request and response headers with the modules logger at ```.Debug``` level.
    open var enableRequestResponseDebug = false

    /**
     Returns either a valid JSON response or an error. Override this method to provide
     other interpretations of error conditions.
     
     - parameter afResponse: Response object from AlamoFire
     - returns: Our response object.
     */
    open func createRemoteResponse(_ afResponse: AFDataResponse<Any>) -> RemoteResponse {
        // First handle network errors
        switch afResponse.result {
        case .failure(let error):
            log.debug("Response contained an error: \(error)")
            var remoteError = RemoteResponse.Errors.networkError
            if (error as NSError).code == NSURLErrorTimedOut {
                remoteError = .networkTimeout
            }
            
            return RemoteResponse(remoteError: remoteError)
            
        case .success:
            let responseContent = afResponse.value
            let statusCode = afResponse.response?.statusCode
            log.verbose("HTTP Status code: \(String(describing: statusCode))")
            
            if let code = statusCode, code < 200 || code >= 300 {
                log.debug("Got non-success HTTP response: \(code)")
                
                var remoteError = RemoteResponse.Errors.serverError
                
                switch code {
                case 401:
                    remoteError = .badCredentials
                case 404:
                    remoteError = .notFound
                default:
                    remoteError = .serverError
                }
                
                let remoteResponse = RemoteResponse(remoteError: remoteError, content: responseContent)
                
                return remoteResponse
            }
            
            if let responseContent = responseContent {
                log.verbose("Received a valid response.")
                return RemoteResponse(content: responseContent)
            } else {
                log.debug("Received invalid or empty JSON response: \(String(describing: afResponse.value))")
                return RemoteResponse(remoteError: RemoteResponse.Errors.badResponse)
            }
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
    open func request(_ method: HTTPMethod, _ url: URLConvertible, parameters: Parameters? = nil, encoding: ParameterEncoding = JSONEncoding.default, headers: HTTPHeaders? = nil, callback: @escaping ((RemoteResponse) -> Void)) {
        
        log.verbose("Making a request to url: \(url)")

        let encodedURLRequest: URLRequestConvertible
        do {
            var urlRequest = try URLRequest(url: url, method: method, headers: headers)

            if let authMapping = getAuthentication() {
                log.verbose("Using access token: \(authMapping.authToken)")
                urlRequest.setValue(authMapping.authToken, forHTTPHeaderField: authMapping.headerName)
            }

            if enableRequestResponseDebug {
                log.debug("Request headers are: \(String(describing: urlRequest.allHTTPHeaderFields))")
            }

            encodedURLRequest = try encoding.encode(urlRequest, with: parameters)
        } catch {
            log.error("Caught an error while constructing a request: \(error)")
            callback(RemoteResponse(remoteError: .clientError))
            return
        }

        manager.request(encodedURLRequest).responseJSON { afResponse in
            log.verbose("Request completed, URL: \(String(describing: afResponse.request?.url)), response: \(afResponse), status code = \(String(describing: afResponse.response?.statusCode))")

            //TODO remove
            debugPrint(afResponse)

            if self.enableRequestResponseDebug {
                if let request = afResponse.request, let response = afResponse.response {
                    log.debug("Response headers are: \(response.allHeaderFields) -- for request URL: \(String(describing: request.url))")
                }
            }

            callback(self.createRemoteResponse(afResponse))
        }

        /*
        manager.request(request).responseJSON { afResponse in
            log.verbose("Request completed, URL: \(afResponse.request?.URL), response: \(afResponse), status code = \(afResponse.response?.statusCode)")

            if self.enableRequestResponseDebug {
                if let request = afResponse.request, let response = afResponse.response {
                    log.debug("Response headers are: \(response.allHeaderFields) -- for request URL: \(request.URL)")
                }
            }

            callback(self.createRemoteResponse(afResponse))
        }
 */
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
    open func getAuthentication() -> AuthenticationMapping? {
        // Base implementation does not nothing
        return nil
    }
    
    /**
    Initializes the base class.
    
    - parameter backgroundSessionId: background session id; eg. com.example.myapp.remote
    - parameter additionalHeaders: optional map of additional (custom) HTTP headers
    - parameter timeout: HTTP response timeout in seconds
    */
    public init(backgroundSessionId: String? = nil, additionalHeaders: [String: AnyObject]? = nil, timeout: TimeInterval = 10) {
        // Set up AlamoFire instance
        var defaultHeaders = Session.default.session.configuration.httpAdditionalHeaders ?? [:]
        if let additionalHeaders = additionalHeaders {
            for (key, value) in additionalHeaders {
                defaultHeaders[key] = value
            }
        }

        let configuration: URLSessionConfiguration

        if let backgroundSessionId = backgroundSessionId {
            configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionId)
        } else {
            configuration = URLSessionConfiguration.default
        }

        configuration.httpAdditionalHeaders = defaultHeaders
        configuration.timeoutIntervalForResource = timeout
        log.verbose("Using default headers: \(defaultHeaders)")
        
        manager = Session(configuration: configuration)
    }
}
