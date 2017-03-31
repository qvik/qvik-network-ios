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

/**
 This class can be used for writing Unit Tests around ```BaseRemoteService``` functionality.
 */
open class MockRemoteService: BaseRemoteService {
    /// This type represents a success/failure condition by path. 
    public typealias OperationMapping = (failureProbability: Double, params: [String: AnyObject]?, successResponse: Any?, failureResponse: Any?, failureError: RemoteResponse.Errors)

    /// Minimum duration (in seconds) for receiving response. Can be used to simulate network latency.
    fileprivate(set) open var minResponseTime: TimeInterval = 0.01

    /// Maximum duration (in seconds) for receiving response. Can be used to simulate network latency.
    fileprivate(set) open var maxResponseTime: TimeInterval = 0.1

    /// Operation success/failure mappings by path.
    fileprivate var operationMappingsByPath = [String: OperationMapping]()

    /// Probability [0, 1] for failure (unless overridden by a mapping)
    open var failureProbability: Double = 0 {
        didSet {
            assert(failureProbability >= 0 && failureProbability <= 1, "Must be within [0, 1]")
        }
    }

    /// Simulated error condition for failures. 
    open var failureError: RemoteResponse.Errors = .serverError

    /// Response content for successful operations (unless overridden by a mapping)
    open var successResponse: Any?

    /// Response content for failed operations (unless overridden by a mapping)
    open var failureResponse: Any?

    /// Compares two AnyObject values for equality, by attempting to cast them to the same types
    /// and comparing the casted values if successful. Only basic types supported.
    fileprivate func compareValues(_ valueA: Any, _ valueB: Any) -> Bool {
        if let intA = valueA as? Int, let intB = valueB as? Int, intA == intB {
            return true
        }

        if let strA = valueA as? String, let strB = valueB as? String, strA == strB {
            return true
        }

        if let dblA = valueA as? Double, let dblB = valueB as? Double, dblA == dblB {
            return true
        }

        return false
    }

    /// Processes an operation mapping and decides on success/failure.
    fileprivate func handleMapping(_ mapping: OperationMapping, requestParams: Parameters?, callback: @escaping ((RemoteResponse) -> Void)) {
        let triggerSuccess = {
            callback(RemoteResponse(content: mapping.successResponse))
        }

        let triggerPossibleFailure = {
            if Double.random() < mapping.failureProbability {
                callback(RemoteResponse(remoteError: mapping.failureError, content: mapping.failureResponse))
            } else {
                triggerSuccess()
            }
        }

        // If failure precondition parameters are given, check for their existence
        if let mappingParams = mapping.params {
            if let requestParams = requestParams {

                var allMatch = true
                for (name, value) in mappingParams {
                    if let reqValue = requestParams[name] {
                        if !compareValues(value, reqValue) {
                            allMatch = false
                            break
                        }
                    }
                }

                if allMatch {
                    triggerPossibleFailure()
                } else {
                    triggerSuccess()
                }
            }
        } else {
            // Mapping params or request params are not present - they dont need to be matched. 
            triggerPossibleFailure()
        }
    }

    /**
     Sets the limits of the simulated network latency. 

     - parameter minResponseTime: Minimum duration (in seconds) for receiving response. Must be > 0.
     - parameter maxResponseTime: Maximum duration (in seconds) for receiving response. Must be > 0.
     */
    open func setResponseTimeLimits(minResponseTime min: TimeInterval, maxResponseTime max: TimeInterval) {
        assert(min > 0, "Must be > 0")
        assert(max > 0, "Must be > 0")
        assert(min <= max, "Must be minResponseTime <= maxResponseTime")

        minResponseTime = min
        maxResponseTime = max
    }

    /**
     Adds an operation mapping by path; this can be used to create success / failure conditions based on
     to which paths requests are made and what parameters are passed. When a request is made to a path for which
     a mapping is found, the operation's params are checked against the ones found in the corresponding mapping;
     if they match, the operation is failed at ```failureProbability``` (0 = never, 1 = always, and everything in between.)
     
     In case of a triggered failure, ```failureResponse``` is set to the the response's parsedResponseJson body and
     ```failureError``` is used as the RemoteError.
     
     In case of success, ```successResponse``` is set to the response's parsedResponseJson body. RemoteError is set to nil.
     */
    open func addOperationMappingForPath(_ path: String, mapping: OperationMapping) {
        assert(mapping.failureProbability >= 0 && mapping.failureProbability <= 1, "Must be in range [0, 1]")

        operationMappingsByPath[path] = mapping
    }

    /**
     Fakes making a request using a random response time timer and preconditions set by the user.

     - parameter method: HTTP method
     - parameter URLString: Request URL
     - parameter parameters: Request parameters
     - parameter encoding: Request encoding
     - parameter headers: Any extra headers
     */
    override open func request(_ method: HTTPMethod, _ url: URLConvertible, parameters: Parameters? = nil, encoding: ParameterEncoding = JSONEncoding.default, headers: HTTPHeaders? = nil, callback: @escaping ((RemoteResponse) -> Void)) {
        // Simulate network latency
        let requestDuration = (maxResponseTime - minResponseTime) * Double.random() + minResponseTime
        log.verbose("Request will take \(requestDuration) seconds")

        let requestUrl: URL
        do {
            requestUrl = try url.asURL()
        } catch {
            log.error("Caught error while extracting url: \(error)")
            callback(RemoteResponse(remoteError: .clientError))
            return
        }

        runOnMainThreadAfter(delay: requestDuration) {
            log.verbose("Request path: \(requestUrl.path), parameters: \(String(describing: parameters))")

            // Check if the path has a registered OperationMapping and use it the handle the request if so
            if let mapping = self.operationMappingsByPath[requestUrl.path] {
                log.debug("Processing mapping for path: \(requestUrl.path)")
                self.handleMapping(mapping, requestParams: parameters, callback: callback)
                return
            }

            // No mapping, lets handle this using the main failure probability.
            if Double.random() < self.failureProbability {
                log.debug("Request will fail")
                callback(RemoteResponse(remoteError: self.failureError, content: self.failureResponse))
            } else {
                log.debug("Request will succeed")
                callback(RemoteResponse(content: self.successResponse))
            }
        }
    }

    /// Constructs a new Mock service.
    public init() {
        super.init(backgroundSessionId: nil, additionalHeaders: nil, timeout: 10)
    }
}
