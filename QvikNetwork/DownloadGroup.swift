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
import QvikSwift

public typealias DownloadGroupProgressCallback = (_ totalBytesRead: UInt64, _ progress: Double) -> Void
public typealias GroupDownloadCompletionCallback = (_ numErrors: Int) -> Void

/**
 A download group can be used to 'group' downloads together; ie, when batch-downloading
 a lot of data at the same time, this class can be used to track their common progress as
 their completion instead of having to include that logic in the application side.

 Do not create DownloadGroup objects directly but instead through a DownloadManager instance.

 All callbacks are called on the main (UI) thread (main queue).

 All the methods in this class are thread safe.
 */
open class DownloadGroup {    
    /// Download progress callback
    open var progressCallback: DownloadGroupProgressCallback?
    
    /// Download completion callback
    open var completionCallback: GroupDownloadCompletionCallback?
    
    /// Arbitrary user data for use by the caller
    open var userData: AnyObject?
    
    /// Reference to the download manager that created this object
    fileprivate(set) var manager: DownloadManager
    
    /// Downloads of this group
    fileprivate(set) open var downloads = [Download]()
    
    // Read/write lock for synchornizing access to downloads array
    fileprivate let lock = ReadWriteLock()
    
    // MARK: Private methods
    
    fileprivate func notifyProgress() {
        var bytesDownloaded: UInt64 = 0
        var completed = true
        var progress = 0.0
        
        let (errors, numDownloads): (Int, Int) = lock.withReadLock {
            var errors = 0

            let numDownloads = self.downloads.count
            
            for download in self.downloads {
                bytesDownloaded += download.bytesDownloaded
                
                if let downloadTotalSize = download.totalSize {
                    progress += Double(download.bytesDownloaded) / Double(downloadTotalSize)
                }
                
                if (download.state != .completed) && (download.state != .failed) {
                    completed = false
                }
                
                if download.error != nil {
                    errors += 1
                }
            }
            
            return (errors, numDownloads)
        }
        
        // Progress will get a value [0, 1]
        progress /= Double(numDownloads)
        log.debug("progress: \(progress), numDownloads = \(numDownloads)")
        
        if let progressCallback = progressCallback {
            progressCallback(bytesDownloaded, progress)
        }
        
        if let completionCallback = completionCallback {
            if completed {
                log.debug("Calling group completionCallback")
                completionCallback(errors)
            }
        }
    }
    
    // MARK: Public methods
    
    /// Indicates whether all the downloads in the group have completed
    open var completed: Bool {
        return lock.withReadLock {
            for download in self.downloads where download.state != .completed {
                return false
            }
            return true
        }
    }
    
    /**
     Starts a new download within the download group.
    */
    open func download(_ url: String, additionalHeaders: [String: String]? = nil) -> Download {
        let download = manager.download(url: url, additionalHeaders: additionalHeaders, progressCallback: { [weak self] (_, _) -> Void  in
            self?.notifyProgress()
        }, completionCallback: { [weak self] (_, _) -> Void in
            self?.notifyProgress()
        })

        download.group = self        

        lock.withWriteLock {
            self.downloads.append(download)
        }
        
        return download
    }
    
    init(manager: DownloadManager) {
        self.manager = manager
    }
}
