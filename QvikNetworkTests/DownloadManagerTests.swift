// The MIT License (MIT)
//
// Copyright (c) 2016 Qvik (www.qvik.fi)
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

/**
 Unit tests for DownloadManager + downloads. Note that for these to succeed, 
 a reasonable network connection is required.
 */
class DownloadManagerTests: XCTestCase {
    var manager: DownloadManager!

    override func setUp() {
        super.setUp()

        QvikNetwork.logLevel = .verbose

        manager = DownloadManager()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()

        manager = nil
    }

    func testSingleDownload() {
        let progressExpectation = expectation(description: "progressBlockCalled")
        let completionExpectation = expectation(description: "completionBlockCalled")

        var download: Download?
        let url = "http://www.google.com" // This url should always exist

        download = manager.download(url: url, progressCallback: { bytesDownloaded, totalBytes in
            log.debug("Download progress: \(bytesDownloaded) / \(totalBytes)")
            progressExpectation.fulfill()
            }, completionCallback: { error, response in
                XCTAssert(download != nil)
                if let contentType = download?.contentType {
                    XCTAssert(contentType.length > 0)
                } else {
                    XCTAssert(false, "Content-Type not set!")
                }
                completionExpectation.fulfill()
        })

        waitForExpectations(timeout: 10.0, handler: nil)
    }
}
