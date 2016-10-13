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

public func == (lhs: Download, rhs: Download) -> Bool {
    return lhs === rhs
}

/**
A single download handle.

Do not create Download objects directly but instead through a DownloadManager/DownloadGroup instances.

All the methods in this class are thread safe.
*/
open class Download: Equatable {
    public enum State {
        case notInitialized
        case starting
        case inProgress
        case failed
        case completed
    }

    public enum Errors: Error {
        case badResponse(statusCode: Int)
    }
    
    /// Download progress callback
    open var progressCallback: DownloadProgressCallback?
    
    /// Download completion callback
    open var completionCallback: DownloadCompletionCallback?
    
    /// Arbitrary user data for use by the caller
    open var userData: AnyObject?
    
    /// URL of this download
    fileprivate(set) open var url: String
    
    /// Download group of this download or nil if single download
    internal(set) open var group: DownloadGroup?
    
    /// State of this download
    internal(set) open var state: State
    
    /// Number of bytes downloaded
    internal(set) open var bytesDownloaded: UInt64
    
    /// Total size of the download
    internal(set) open var totalSize: UInt64?

    /// The Content-Type of this download. Set upon completion. 
    internal(set) open var contentType: String?
    
    /// Error that occurred while downloading or nil if none
    internal(set) open var error: Error?
    
    init(url: String) {
        self.url = url
        self.state = .notInitialized
        self.bytesDownloaded = 0
    }
}
