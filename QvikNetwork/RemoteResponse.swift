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

/**
 Represents a response from the server.
*/
open class RemoteResponse {
    public enum Errors: Error {
        case clientError
        case networkError
        case networkTimeout
        case badCredentials
        case serverError
        case notFound
        case badResponse
    }
    
    /// Type of error in the API call, or nil if success
    fileprivate(set) open var remoteError: Errors?
    
    /// Response content
    fileprivate(set) open var content: Any?

    /// Convenience accessor for dictionary (JSON object) response JSON
    open var contentJson: [String: AnyObject]? {
        return content as? [String: AnyObject]
    }

    /// Convenience accessor for array (JSON array) response JSON
    open var contentJsonArray: [[String: AnyObject]]? {
        return content as? [[String: AnyObject]]
    }

    /// Whether the request was successful or not
    open var success: Bool {
        return (remoteError == nil)
    }
    
    public init(content: Any?) {
        self.content = content
    }

    public init(remoteError: Errors) {
        self.remoteError = remoteError
    }

    public init(remoteError: Errors?, content: Any?) {
        self.remoteError = remoteError
        self.content = content
    }
}

extension RemoteResponse: CustomStringConvertible {
    public var description: String {
        return "RemoteResponse: remoteError: \(String(describing: remoteError)), content: \(String(describing: content))"
    }
}
