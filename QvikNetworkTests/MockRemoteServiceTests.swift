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

import XCTest

/// Example "remote service" used for testing
class RemoteService {
    let remoteImpl: BaseRemoteService
    let baseUrl = "http://www.site.com"

    func list(_ callback: @escaping ((RemoteResponse) -> Void)) {
        let url = "\(baseUrl)/list"

        remoteImpl.request(.get, url, parameters: nil, callback: callback)
    }

    func update(name: String, age: Int, married: Bool, callback: @escaping ((RemoteResponse) -> Void)) {
        let url = "\(baseUrl)/update"

        let params: [String: AnyObject] = ["name": name as AnyObject, "age": age as AnyObject, "married": married as AnyObject]

        remoteImpl.request(.post, url, parameters: params, callback: callback)
    }

    init(remoteImpl: BaseRemoteService) {
        self.remoteImpl = remoteImpl
    }
}

class MockRemoteServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()

        QvikNetwork.logLevel = .verbose
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testSuccess() {
        let remoteService = RemoteService(remoteImpl: MockRemoteService())

        let expectation = self.expectation(description: "success")

        remoteService.list { response in
            if response.success {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testFailure() {
        let mockService = MockRemoteService()

        // Set every request to fail always
        mockService.failureProbability = 1.0

        let remoteService = RemoteService(remoteImpl: mockService)

        let expectation = self.expectation(description: "failure")

        remoteService.list { response in
            // The request must fail in order for the test to pass
            if !response.success {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testSimplePathMapping() {
        let mockService = MockRemoteService()

        // Create a precondition that /update always fails
        mockService.addOperationMappingForPath("/update", mapping: (failureProbability: 1.0, params: nil, successResponse: ["status": "ok"], failureResponse: ["status": "failed"], failureError: .serverError))
        let remoteService = RemoteService(remoteImpl: mockService)

        let listMustSucceed = expectation(description: "listMustSucceed")
        let updateMustFail = expectation(description: "updateMustFail")

        remoteService.list { response in
            if response.success {
                listMustSucceed.fulfill()
            }
        }

        remoteService.update(name: "Gary", age: 44, married: true) { response in
            if !response.success {
                updateMustFail.fulfill()
            }
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testPathAndParamMapping() {
        let mockService = MockRemoteService()

        // Create a precondition that /update always fails if params age = 17, married = true are set
        mockService.addOperationMappingForPath("/update", mapping: (failureProbability: 1.0, params: ["age": 17 as AnyObject, "married": true as AnyObject], successResponse: ["status": "ok"], failureResponse: ["status": "failed"], failureError: .serverError))

        // Set default success response content
        mockService.successResponse = ["status": "ok"]

        let remoteService = RemoteService(remoteImpl: mockService)

        let mustSucceed = expectation(description: "Must succeed with these params")
        let mustFail = expectation(description: "Must fail with these params")

        // Start a request that should succeed
        remoteService.update(name: "Leslie", age: 18, married: true) { response in
            if response.success {
                // Also check that proper success response content is in place
                if let status = response.contentJson?["status"] as? String, status == "ok" {
                    mustSucceed.fulfill()
                }
            }
        }

        // Start a request that should fail
        remoteService.update(name: "Leslie", age: 17, married: true) { response in
            if !response.success {
                // Also check that proper failure content is in place
                if let status = response.contentJson?["status"] as? String, status == "failed" {
                    mustFail.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }
}
