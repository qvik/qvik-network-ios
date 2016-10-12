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
import SwiftGifOrigin

// Exceptionally, include test cases for the external dependency 'SwiftGif' as
// this library has experienced instability in the past.
class SwiftGifTests: XCTestCase {
    override func setUp() {
        super.setUp()

    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    fileprivate func loadGif(_ name: String) -> UIImage? {
        let bundle = Bundle(for: type(of: self))
        let path = bundle.path(forResource: name, ofType: "gif")!
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        return UIImage.gifWithData(data)
    }

    func testEmpty() {
        let empty = loadGif("empty")
        XCTAssert(empty == nil)
    }

    func testWorking() {
        let working = loadGif("working")
        XCTAssert(working != nil)
    }

    func testBroken() {
        let broken = loadGif("randombytes_broken")
        XCTAssert(broken == nil)
    }

    func testAnimated() {
        let animated = loadGif("animated")
        XCTAssert(animated != nil)
    }
}
