// The MIT License (MIT)
//
// Copyright (c) 2015 Qvik (www.qvik.fi)
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

import UIKit
import QvikSwift
import CryptoSwift

/**
Disk-backed image cache with functionality to retrieve the requested
image over the internet if not found.

The images are accessed by their original URLs. The
images are stored on disk as JPEGs, filenames are MD5 hashes of the tokens.

Whenever an image is loaded into the memory cache (and is thus available for use),
cacheImageLoadedNotification is sent with imageParam user info key specifying the image
and urlParam specifying the related image URL.

All notifications are sent on the main (UI) thread.

All the methods of this class are thread safe.
*/
public class ImageCache: NSObject {
    public enum FileFormat: String {
        case JPEG = "image/jpeg"
        case PNG = "image/png"
    }
    
    public static let cacheImageLoadedNotification = "cacheImageLoadedNotification"
    public static let cacheImageLoadFailedNotification = "cacheImageLoadFailedNotification"
    public static let urlParam = "urlParam"
    
    private static let singletonInstance = ImageCache()
    
    /// Returns the absolute path of the image disk cache directory
    private(set) public var path: NSString
    
    /** 
    Maximum dimensions for images to store on disk; any image with width/height
    larger than these are downscaled after downloading. Aspect ratio is retained.
    By default this is not set.
    */
    public var maximumImageDimensions: CGSize?

    /**
    Maximum age for unused files in the file cache, in seconds. Default is 30 days.
    */
    public var maximumUnusedFileAge: NSTimeInterval = 30 * 24 * 60 * 60
    
    /**
    Format to store the downloaded files. By default it is not set and images
    of supported formats (see FileFormat enum) are written to the disk as-is.
    */
    public var fileFormat: FileFormat?
    
    private let fileManager = NSFileManager.defaultManager()
    
    // The memory cache dictionary
    private var inMemoryCache = [String: UIImage]()
    
    // Lock for synchronizing access to the memory cache
    private let lock = ReadWriteLock()
    
    private let downloadManager = DownloadManager.sharedInstance()
    
    // MARK: Private methods
    
    /// Makes sure the image cache directory exists
    private func checkCacheDirExists() {
        do {
            var isDirectory: ObjCBool = true
            var exists = fileManager.fileExistsAtPath(path as String, isDirectory: &isDirectory)
            if exists && !isDirectory {
                // This should obviously never happen ..
                log.error("File system entry for image cache path is a file!")
                try fileManager.removeItemAtPath(path as String)
                exists = false
            }
            
            if !exists {
                try fileManager.createDirectoryAtPath(path as String, withIntermediateDirectories: true, attributes: nil)
            }
        } catch let error {
            log.error("Failed to create image cache directory \(path), error: \(error)")
            assertionFailure("Failed to create image cache directory")
        }
    }
    
    // Responds to memory warning; clears the memory cache
    func memoryWarningNotification(notification: NSNotification) {
        lock.withWriteLock {
            self.inMemoryCache.removeAll(keepCapacity: false)
        }
    }

    // Checks disk cache and removes entries older than fileMaxAge.
    private func reapDiskCache() {
        let error: NSError? = nil
        let contents: [String]?
        do {
            contents = try fileManager.contentsOfDirectoryAtPath(path as String)
        } catch let error as NSError {
            log.error("Failed to get contents of disk cache directory, error: \(error)")
            return
        }

        for entry in contents! {
            let filePath = path.stringByAppendingPathComponent(entry)
            
            let attributes: NSDictionary?
            
            do {
                attributes = try fileManager.attributesOfItemAtPath(filePath)
            } catch let error as NSError {
                log.error("Failed to get attributes of file at path: \(filePath), error: \(error)")
                attributes = nil
            }
            if let attributes = attributes {
                if let modified = attributes.fileModificationDate() {
                    if -modified.timeIntervalSinceNow > maximumUnusedFileAge {
                        log.debug("Removing old unusued file at path: \(filePath)")
                        do {
                            try fileManager.removeItemAtPath(filePath)
                        } catch let error as NSError {
                            log.error("Failed to remove file at path: \(filePath), error: \(error)")
                        }
                    }
                }
            } else {
                log.error("Failed to read attributes of file at path \(filePath), error: \(error)")
            }
        }
    }
    
    private func insertToMemoryCache(image image: UIImage, url: String) {
        lock.withWriteLock {
            self.inMemoryCache[url] = image
        }
        
        log.debug("Inserted image to the in-memory cache with the URL key \(url), image: \(image)")
        
        runOnMainThread {
            log.debug("Sending notification \(ImageCache.cacheImageLoadedNotification), object: \(self), param: \(ImageCache.urlParam), url: \(url)")
            NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadedNotification, object: self, userInfo: [ImageCache.urlParam: url])
        }
    }
    
    private func writeImageToDisk(image image: UIImage, url: String, response: NSHTTPURLResponse?, data: NSData?) {
        runInBackground {
            self.checkCacheDirExists()
            
            let filePath = self.path.stringByAppendingPathComponent(url.md5()!)

            do {
                try self.fileManager.removeItemAtPath(filePath) // First remove the file if it exists
            } catch {
                // Not found, can ignore
            }
            
            let contentType = (response?.allHeaderFields["content-type"] as? String)?.lowercaseString
            
            // If fileFormat matches the response's content type and data is set, we can directly write the data
            if ((self.fileFormat == nil) || (contentType == self.fileFormat!.rawValue)) && (data != nil) {
                log.debug("Content type matches or is not set and data is set - writing as pass-through")
                data!.writeToFile(filePath, atomically: true)
            } else {
                // File format does not match or image has been downscaled; we must re-compress into selected format
                let fileFormat = self.fileFormat ?? FileFormat.PNG
            
                if fileFormat == .JPEG {
                    if !UIImageJPEGRepresentation(image, 0.9)!.writeToFile(filePath, atomically: true) {
                        log.debug("Failed to write JPEG file \(filePath)")
                    } else {
                        log.debug("JPEG image written to path \(filePath)")
                    }
                } else {
                    if !UIImagePNGRepresentation(image)!.writeToFile(filePath, atomically: true) {
                        log.debug("Failed to write PNG file \(filePath)")
                    } else {
                        log.debug("PNG image written to path \(filePath)")
                    }
                }
            }
        }
    }
    
    // Fetches an image from an URL, storing it to disk/in-memory caches if successful and notifying on completion
    private func fetchImage(url url: String) {
        log.debug("Fetching image from URL: \(url)")
        
        self.downloadManager.download(url: url, additionalHeaders: nil, progressCallback: nil) { (error, response, data) -> () in
            if let error = error {
                log.warning("Image download failed for URL: \(url), error: \(error)")
                NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
            } else {
                if let data = data {
                    log.debug("Response headers: \(response!.allHeaderFields)")
                    log.debug("Image downloaded, storing it in the cache..")
                    runInBackground {
                        var image = UIImage(data: data)
                        if image == nil {
                            log.error("Failed to parse the image data into an image")
                            NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
                            return
                        }
                        
                        var data: NSData? = data
                        
                        if let maximumImageDimensions = self.maximumImageDimensions {
                            log.debug("Downscaling the downloaded image to max size: \(maximumImageDimensions)")
                            image = image!.scaleDown(maxSize: maximumImageDimensions)
                            data = nil
                        }
                        
                        // Insert the image to the in-memory cache and notify about successful load
                        self.insertToMemoryCache(image: image!, url: url)
                        
                        // Asynchronously write the image to the disk cache
                        self.writeImageToDisk(image: image!, url: url, response: response, data: data)
                    }
                } else {
                    log.error("Missing image data in response!")
                    NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
                }
            }
        }
    }
    
    // MARK: Public methods

    /// Clears the entire cache's contents. Mostly useful for debugging purposes.
    public func clearCache() {
        let contents: [String]?
        do {
            contents = try fileManager.contentsOfDirectoryAtPath(path as String)
        } catch let error {
            log.error("Failed to get contents of disk cache directory, error: \(error)")
            return
        }
        
        for entry in contents! {
            let filePath = path.stringByAppendingPathComponent(entry)
            do {
                try fileManager.removeItemAtPath(filePath)
            } catch let error {
                log.error("Failed to remove file in cache, error: \(error)")
            }
        }
    }
    
    /**
    Returns an image matching the given token from the cache. If not found, returns nil.
    Only in-memory cache is accessed synchronously; if the image is loaded from disk or retrieved over the
    internet, this is done asynchronously. When asynchronous load succeeds, 
    cacheImageLoadedNotification is sent with urlParam set.
    
    If asynchronous load fails, cacheImageLoadFailedNotification is sent, with urlParam set.
    
    - parameter fetch: if YES, treats the token as an URL and attempts to fetch the image over the internet.
    */
    public func getImage(url url: String, fetch: Bool = true) -> UIImage? {
        log.debug("getting image for url: \(url)")
        
        // Check if the image is found in the in-memory cache
        let image = lock.withReadLock {
            return self.inMemoryCache[url]
        }
        
        if image != nil {
            log.debug("Image found in in-memory cache.")
            return image
        }
        
        runInBackground {
            let filePath = self.path.stringByAppendingPathComponent(url.md5()!)
            
            if let image = UIImage(contentsOfFile: filePath) {
                // Image found in disk cache; 'touch' the file to update its timestamp
                log.debug("Image found on disk in path \(filePath)")
                do {
                    try self.fileManager.setAttributes([NSFileModificationDate: NSDate()], ofItemAtPath: filePath)
                } catch let error {
                    log.error("Failed to update last modification date of file \(filePath), error: \(error)")
                }
                
                self.insertToMemoryCache(image: image, url: url) // Will send loaded -notification
            } else {
                if fetch {
                    log.debug("Image not found on disk.")
                    if self.downloadManager.hasPendingDownload(url: url) {
                        log.debug("Already fetching image from url \(url)")
                    } else {
                        self.fetchImage(url: url)
                    }
                }
            }
        }
        
        return nil
    }

    /// Returns a shared, singleton instance
    public class func sharedInstance() -> ImageCache {
        return singletonInstance
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    /**
    Creates a new ImageCache.
    
    - parameter directory: sub directory path to store the image files - a relative path 
    (of a directory, not deeper) under the app's documents directory. If not supplied, 
    "images" will be used.
    */
    public init(imagePath: String? = nil) {
        let imagePath = imagePath ?? "images"
        let paths = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)
        let cacheRootDirectory = paths[0] as NSString
        path = cacheRootDirectory.stringByAppendingPathComponent(imagePath)
        
        super.init()
        
        log.debug("My disk cache path is: \(path)")
        
        checkCacheDirExists()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "memoryWarningNotification:", name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        
        reapDiskCache()
    }
}
