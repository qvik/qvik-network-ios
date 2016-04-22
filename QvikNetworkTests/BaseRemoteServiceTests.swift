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

    func list(callback: ((RemoteResponse) -> Void)) {
        let url = "\(baseUrl)/list"

        remoteImpl.request(.GET, url, parameters: nil, callback: callback)
    }

    func update(name: String, callback: ((RemoteResponse) -> Void)) {
        let url = "\(baseUrl)/update"

        let params = ["name": name]

        remoteImpl.request(.POST, url, parameters: params, callback: callback)
    }

    init(remoteImpl: BaseRemoteService) {
        self.remoteImpl = remoteImpl
    }
}

class BaseRemoteServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()

        QvikNetwork.logLevel = .Verbose
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testSuccess() {
        let remoteService = RemoteService(remoteImpl: MockRemoteService())

        let expectation = expectationWithDescription("success")

        remoteService.list { response in
            if response.success {
                expectation.fulfill()
            }
        }

        waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFailure() {
        let mockService = MockRemoteService()
        mockService.failureProbability = 1.0

        let remoteService = RemoteService(remoteImpl: mockService)

        let expectation = expectationWithDescription("failure")

        remoteService.list { response in
            if !response.success {
                expectation.fulfill()
            }
        }

        waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testSimplePathMapping() {
        let mockService = MockRemoteService()
        mockService.addOperationMappingForPath("/update", mapping: (failureProbability: 1.0, params: nil, successResponse: ["status": "ok"], failureResponse: ["status": "failed"], failureError: .ServerError))
        let remoteService = RemoteService(remoteImpl: mockService)

        let listMustSucceed = expectationWithDescription("listMustSucceed")
        let updateMustFail = expectationWithDescription("updateMustFail")

        remoteService.list { response in
            if response.success {
                listMustSucceed.fulfill()
            }
        }

        remoteService.update("Gary") { response in
            if !response.success {
                updateMustFail.fulfill()
            }
        }

        waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}
