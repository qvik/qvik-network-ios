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

public typealias DownloadProgressCallback = (_ totalBytesRead: UInt64, _ totalBytesExpectedToRead: UInt64) -> ()
public typealias DownloadCompletionCallback = (_ error: Error?, _ response: DataResponse<Data>?) -> ()

/**
 High level HTTP download manager that supports grouping several downloads
 for easier state/progress tracking and completion handling.
 
 All callbacks are called on the main (UI) thread (main queue).

 Internally the implementation uses AlamoFire the de facto HTTP library.

 All the methods in this class are thread safe.
 */
open class DownloadManager {
    open static let errorDomain = "DownloadManager"

    /// Default singleton instance
    open static let `default` = DownloadManager()

    /// Alamofire session manager used to handle downloads
    fileprivate let manager: SessionManager
    
    /// Currently pending downloads
    fileprivate(set) open var pendingDownloads = [Download]()
    
    // Read/write lock for synchornizing access to pending downloads array
    fileprivate let lock = ReadWriteLock()

    /// Checks whether there is a pending download for a given URL.
    open func hasPendingDownload(_ url: String) -> Bool {
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
    open func createGroup() -> DownloadGroup {
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
    @discardableResult open func download(url: String, additionalHeaders: [String: String]? = nil, progressCallback: DownloadProgressCallback?, completionCallback: DownloadCompletionCallback?) -> Download {

        let download = Download(url: url)
        
        lock.withWriteLock {
            self.pendingDownloads.append(download)
        }

        log.debug("Starting download for url '\(url)'")

        manager.request(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: additionalHeaders).downloadProgress { progress in
            log.debug("Download progress: url: \(url), \(progress.fractionCompleted * 100)%")

            download.bytesDownloaded = UInt64(progress.completedUnitCount)
            download.totalSize = (progress.totalUnitCount > 0) ? UInt64(progress.totalUnitCount) : 0
            
            if let progressCallback = download.progressCallback {
                progressCallback(UInt64(progress.completedUnitCount), UInt64(progress.totalUnitCount))
            }
            
            if let progressCallback = progressCallback {
                progressCallback(UInt64(progress.totalUnitCount), UInt64(progress.totalUnitCount))
            }
        }.responseData { afResponse in
            let contentType = afResponse.response?.allHeaderFields["Content-Type"] as? String
            download.contentType = contentType

            log.debug("Request completed: url: \(url), response = \(afResponse), http response: \(String(describing: afResponse.response)), contentType = \(String(describing: contentType))")

            var error = afResponse.result.error

            if let error = error {
                download.state = .failed
                download.error = error
            } else {
                if let statusCode = afResponse.response?.statusCode {
                    if statusCode >= 200 && statusCode < 300 {
                        // Success
                        download.state = .completed
                    } else {
                        download.state = .failed
                        error = Download.Errors.badResponse(statusCode: statusCode)
                    }
                }
            }

            // Download completed, remove it from the pending -array
            self.lock.withWriteLock {
                if let index = self.pendingDownloads.index(of: download) {
                    self.pendingDownloads.remove(at: index)
                }
            }
            
            if let completionCallback = download.completionCallback {
                completionCallback(error, afResponse)
            }

            if let completionCallback = completionCallback {
                completionCallback(error, afResponse)
            }

            log.verbose("Download completed, callbacks called.")
        }
        
        return download
    }

    public init(bgSessionId: String? = nil) {
        // Set up AlamoFire instance
        let defaultHeaders = SessionManager.default.session.configuration.httpAdditionalHeaders ?? [:]

        let bgSessionId = bgSessionId ?? "com.qvik.downloadManager"
        let configuration = URLSessionConfiguration.background(withIdentifier: bgSessionId)
        configuration.httpAdditionalHeaders = defaultHeaders
        configuration.timeoutIntervalForResource = 30

        log.debug("Constructing SessionManager with defaultHeaders: \(defaultHeaders)")
        
        manager = SessionManager(configuration: configuration)
    }
}
