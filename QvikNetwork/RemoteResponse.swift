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
public class RemoteResponse {
    public enum RemoteError {
        case ClientError
        case NetworkError
        case NetworkTimeout
        case BadCredentials
        case ServerError
        case NotFound
    }
    
    /// Type of error in the API call, or nil if success
    private(set) public var remoteError: RemoteError?
    
    /// Underlying NSError, if any
    private(set) public var nsError: NSError?
    
    /// Response JSON, or nil if no JSON in response
    private(set) public var parsedResponseJson: AnyObject?

    /// Convenience accessor for dictionary (JSON object) response JSON
    public var parsedJson: [String: AnyObject]? {
        return parsedResponseJson as? [String: AnyObject]
    }

    /// Convenience accessor for array (JSON array) response JSON
    public var parsedJsonArray: [[String: AnyObject]]? {
        return parsedResponseJson as? [[String: AnyObject]]
    }

    /// Whether the request was successful or not
    public var success: Bool {
        return (remoteError == nil) && (nsError == nil)
    }
    
    public init() {
    }
    
    public init(json: AnyObject?) {
        self.parsedResponseJson = json
    }

    public init(remoteError: RemoteError) {
        self.remoteError = remoteError
    }

    public init(remoteError: RemoteError?, json: AnyObject?) {
        self.remoteError = remoteError
        self.parsedResponseJson = json
    }

    public init(nsError: NSError?, remoteError: RemoteError?, json: AnyObject?) {
        self.nsError = nsError
        self.remoteError = remoteError
        self.parsedResponseJson = json
    }
}

extension RemoteResponse: CustomStringConvertible {
    public var description: String {
        return "RemoteResponse: remoteError: \(remoteError), nsError: \(nsError), parsedJson: \(parsedJson)"
    }
}
