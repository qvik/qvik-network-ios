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

public typealias DownloadProgressCallback = (bytesRead: UInt64, totalBytesRead: UInt64, totalBytesExpectedToRead: UInt64) -> ()
public typealias DownloadCompletionCallback = (error: NSError?, response: NSHTTPURLResponse?, data: NSData?) -> ()

/**
High level HTTP download manager that supports grouping several downloads
for easier state/progress tracking and completion handling. 

Internally the implementation uses AlamoFire the de facto HTTP library.

All the methods in this class are thread safe.
*/
public class DownloadManager {
    public static let errorDomain = "DownloadManager"
    
    private static let staticInstance = DownloadManager()
    
    private let manager: Alamofire.Manager
    
    /// Currently pending downloads
    private(set) public var pendingDownloads = [Download]()
    
    // Read/write lock for synchornizing access to pending downloads array
    private let lock = ReadWriteLock()

    /// Returns the shared instance
    public class func sharedInstance() -> DownloadManager {
        return staticInstance
    }

    /// Checks whether there is a pending download for a given URL.
    public func hasPendingDownload(url url: String) -> Bool {
        return lock.withReadLock {
            for download in self.pendingDownloads {
                if download.url == url {
                    return true
                }
            }
            return false
        }
    }
    
    /**
    Create a new download group. Use the returned group object to schedule actual downloads.
    
    - returns: a new group object
    */
    public func createGroup() -> DownloadGroup {
        let group = DownloadGroup(manager: self)
        
        return group
    }
    
    /**
    Start a download from the given url. Call this method directly to schedule a single download, 
    or call DownloadGroup.download() to schedule a grouped download.
    
    - parameter url: URL of the file to download
    - parameter additionalHeaders: Any additional/custom headers to add to the request or nil for none
    - parameter progressCallback: download progress callback for this particular download
    - parameter completionCallback: download completion callback for this particular download
    */
    public func download(url url: String, additionalHeaders: [String: String]? = nil, progressCallback: DownloadProgressCallback?, completionCallback: DownloadCompletionCallback?) -> Download {
        log.debug("Starting download for url '\(url)'")
        
        let download = Download(url: url)
        
        lock.withWriteLock {
            self.pendingDownloads.append(download)
        }
        
        manager.request(.GET, url, parameters: nil, encoding: .URL, headers: additionalHeaders).progress { bytesRead, totalBytesRead, totalBytesExpectedToRead in
            log.debug("Download progress: url: \(url), \(totalBytesRead)/\(totalBytesExpectedToRead)")

            download.bytesDownloaded = UInt64(totalBytesRead)
            download.totalSize = (totalBytesExpectedToRead > 0) ? UInt64(totalBytesExpectedToRead) : 0
            
            if let progressCallback = download.progressCallback {
                progressCallback(bytesRead: UInt64(bytesRead), totalBytesRead: UInt64(totalBytesRead), totalBytesExpectedToRead: UInt64(totalBytesExpectedToRead))
            }
            
            if let progressCallback = progressCallback {
                progressCallback(bytesRead: UInt64(bytesRead), totalBytesRead: UInt64(totalBytesRead), totalBytesExpectedToRead: UInt64(totalBytesExpectedToRead))
            }
        }.response { request, response, data, error in
            log.debug("Request completed: url: \(url), error = \(error), response = \(response)")

            var nsError = error
            
            if let nsError = nsError {
                download.state = .Failed
                download.error = nsError
            } else {
                if let statusCode = response?.statusCode {
                    if statusCode >= 200 && statusCode < 300 {
                        // Success
                        download.state = .Completed
                    } else {
                        download.state = .Failed
                        nsError = NSError(domain: DownloadManager.errorDomain, code: statusCode, userInfo: nil)
                    }
                }
            }
            
            // Download completed, remove it from the pending -array
            self.lock.withWriteLock {
                if let index = self.pendingDownloads.indexOf(download) {
                    self.pendingDownloads.removeAtIndex(index)
                }
            }
            
            if let completionCallback = download.completionCallback {
                completionCallback(error: nsError, response: response, data: data)
            }
            
            if let completionCallback = completionCallback {
                completionCallback(error: nsError, response: response, data: data)
            }
        }
        
        return download
    }

    public init(bgSessionId: String? = nil) {
        // Set up AlamoFire instance
        let defaultHeaders = Alamofire.Manager.sharedInstance.session.configuration.HTTPAdditionalHeaders ?? [:]
        
        let bgSessionId = bgSessionId ?? "com.qvik.downloadManager"
        let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier(bgSessionId)
        configuration.HTTPAdditionalHeaders = defaultHeaders
        configuration.timeoutIntervalForResource = 30
        
        manager = Alamofire.Manager(configuration: configuration)
    }
}
