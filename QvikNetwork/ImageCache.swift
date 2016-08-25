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

import UIKit
import CryptoSwift
import SwiftGifOrigin

import QvikSwift

/// GIF mime type; GIFs are only stored as passthrough, never encoded to.
private let gifMimeType = "image/gif"
private let gifExtension = ".gif"

/**
Disk-backed image cache with functionality to retrieve the requested
image over the internet if not found.

The images are accessed by their original URLs. The
images are stored on disk as PNG/JPEGs (with GIF passthrough suoported), filenames are MD5 hashes of the tokens.

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
    
    /// Quality of JPEG compression; must be in range [0, 1]. Default value is 0.9.
    public var jpegQuality: CGFloat = 0.9 {
        didSet {
            assert(jpegQuality >= 0.0, "Allowed value range is 0..1")
            assert(jpegQuality <= 1.0, "Allowed value range is 0..1")
        }
    }
    
    /// The memory cache dictionary
    private var inMemoryCache = [String: UIImage]()
    
    /// Lock for synchronizing access to the in-memory cache
    private let lock = ReadWriteLock()
    
    /// GCD queue for performing all disk operations
    private let diskOperationQueue: dispatch_queue_t
    
    private let fileManager = NSFileManager.defaultManager()
    private let downloadManager = DownloadManager.sharedInstance()
    
    // MARK: Private methods
    
    /// Creates a file path for a given URL. 
    private func getFilePath(url url: String) -> String {
        return path.stringByAppendingPathComponent(url.md5())
    }
    
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
    
    /// Responds to memory warning; clears the memory cache
    func memoryWarningNotification(notification: NSNotification) {
        log.info("Memory warning received; dumping cache contents.")
        
        lock.withWriteLock {
            self.inMemoryCache.removeAll(keepCapacity: false)
        }
    }

    /// Checks disk cache and removes entries older than fileMaxAge.
    private func reapDiskCache() {
        dispatch_async(diskOperationQueue) {
            let error: NSError? = nil
            let contents: [String]?
            
            do {
                contents = try self.fileManager.contentsOfDirectoryAtPath(self.path as String)
            } catch let error as NSError {
                log.error("Failed to get contents of disk cache directory, error: \(error)")
                return
            }
            
            for entry in contents! {
                let filePath = self.path.stringByAppendingPathComponent(entry)
                
                let attributes: NSDictionary?
                
                do {
                    attributes = try self.fileManager.attributesOfItemAtPath(filePath)
                } catch let error as NSError {
                    log.error("Failed to get attributes of file at path: \(filePath), error: \(error)")
                    attributes = nil
                }
                if let attributes = attributes {
                    if let modified = attributes.fileModificationDate() {
                        if -modified.timeIntervalSinceNow > self.maximumUnusedFileAge {
                            log.verbose("Removing old unused file at path: \(filePath)")
                            do {
                                try self.fileManager.removeItemAtPath(filePath)
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
    }
    
    /// Inserts the image synchronously to the in-memory cache in a thread safe 
    /// manner and sends a loading notification
    private func insertToMemoryCache(image image: UIImage, url: String) {
        lock.withWriteLock {
            self.inMemoryCache[url] = image
        }
        
        log.verbose("Inserted image to the in-memory cache with the URL key \(url)")
        
        runOnMainThread {
            log.verbose("Sending notification \(ImageCache.cacheImageLoadedNotification), object: \(self), param: \(ImageCache.urlParam), url: \(url)")
            NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadedNotification, object: self, userInfo: [ImageCache.urlParam: url])
        }
    }
    
    /// Encodes image data to the format specified by ´´´self.fileFormat´´´ and writes it to the disk 
    /// to a given path.
    private func encodeAndWriteImageToDisk(image image: UIImage, filePath: String) {
        dispatch_async(diskOperationQueue) {
            autoreleasepool {
                let fileFormat = self.fileFormat ?? FileFormat.PNG
                
                if fileFormat == .JPEG {
                    if !UIImageJPEGRepresentation(image, self.jpegQuality)!.writeToFile(filePath, atomically: true) {
                        log.verbose("Failed to write JPEG file \(filePath)")
                    } else {
                        log.verbose("JPEG image written to path \(filePath)")
                    }
                } else {
                    if !UIImagePNGRepresentation(image)!.writeToFile(filePath, atomically: true) {
                        log.verbose("Failed to write PNG file \(filePath)")
                    } else {
                        log.verbose("PNG image written to path \(filePath)")
                    }
                }
            }
        }
    }
    
    /// Figure out the type of the file in the response and write to the disk, possibly avoiding the
    /// re-encoding in case the cache was configured to use the file format in the response
    private func writeResponseImageToDisk(image image: UIImage, url: String, response: NSHTTPURLResponse?, data: NSData?) {
        dispatch_async(diskOperationQueue) {
            self.checkCacheDirExists()
            
            let filePath = self.getFilePath(url: url)
            
            do {
                try self.fileManager.removeItemAtPath(filePath) // First remove the file if it exists
            } catch {
                // Not found, can ignore
            }
            
            let contentType = (response?.allHeaderFields["content-type"] as? String)?.lowercaseString
            
            // If fileFormat matches the response's content type and data is set, we can directly write the data
            if ((contentType == gifMimeType) || (self.fileFormat == nil) || (contentType == self.fileFormat!.rawValue)) && (data != nil) {
                log.verbose("Content type matches (or is GIF) or is not set and data is set - writing as pass-through")
                data!.writeToFile(filePath, atomically: true)
            } else {
                // File format does not match or image has been downscaled; we must re-compress into selected format
                self.encodeAndWriteImageToDisk(image: image, filePath: filePath)
            }
        }
    }
    
    /// Fetches an image from an URL, storing it to disk/in-memory caches if 
    /// successful and notifying on completion
    private func fetchImage(url url: String) {
        log.verbose("Fetching image from URL: \(url)")
        
        self.downloadManager.download(url: url, additionalHeaders: nil, progressCallback: nil) { (error, response, data) -> () in
            if let error = error {
                log.warning("Image download failed for URL: \(url), error: \(error)")
                NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
            } else {
                if let data = data {
                    log.verbose("Response headers: \(response!.allHeaderFields)")
                    log.verbose("Image downloaded, storing it in the cache..")
                    runInBackground {
                        let isGif = ((response?.allHeaderFields["content-type"] as? String)?.lowercaseString == gifMimeType)

                        var image: UIImage?
                        
                        if isGif {
                            log.verbose("Creating a GIF image from response data")
                            image = UIImage.gifWithData(data)
                        } else {
                            image = UIImage(data: data)
                        }
                        
                        if image == nil {
                            log.error("Failed to parse the image data into an image")
                            NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
                            return
                        }
                        
                        var data: NSData? = data
                        
                        if let maximumImageDimensions = self.maximumImageDimensions where !isGif {
                            log.verbose("Downscaling the downloaded image to max size: \(maximumImageDimensions)")
                            image = image!.scaleDown(maxSize: maximumImageDimensions)
                            data = nil
                        }
                        
                        // Insert the image to the in-memory cache and notify about successful load
                        self.insertToMemoryCache(image: image!, url: url)
                        
                        // Asynchronously write the image to the disk cache
                        self.writeResponseImageToDisk(image: image!, url: url, response: response, data: data)
                    }
                } else {
                    log.error("Missing image data in response!")
                    NSNotificationCenter.defaultCenter().postNotificationName(ImageCache.cacheImageLoadFailedNotification, object: self, userInfo: [ImageCache.urlParam: url])
                }
            }
        }
    }
    
    // MARK: Public methods

    /**
     Clears the entire cache's contents - on memory and optionally on disk too. This is a drastic
     measure and mostly useful for special conditions such as debugging purposes and making sure
     no memory is being clung to by the cache.
     
     - parameters clearDiskContents: whether to clear disk contents too. Defaults to ```true```.
     */
    public func clearCache(clearDiskContents clearDiskContents: Bool = true) {
        lock.withWriteLock {
            self.inMemoryCache.removeAll(keepCapacity: false)
        }

        if !clearDiskContents {
            return
        }

        dispatch_async(diskOperationQueue) {
            let contents: [String]?
            do {
                contents = try self.fileManager.contentsOfDirectoryAtPath(self.path as String)
            } catch let error {
                log.error("Failed to get contents of disk cache directory, error: \(error)")
                return
            }
            
            for entry in contents! {
                let filePath = self.path.stringByAppendingPathComponent(entry)
                do {
                    if self.fileManager.fileExistsAtPath(filePath) {
                        try self.fileManager.removeItemAtPath(filePath)
                    }
                } catch let error {
                    log.error("Failed to remove file on disk, error: \(error)")
                }
            }            
        }
    }
    
    /**
     Removes an image by given url from the in-memory cache and optionally from the disk also.
     
     Can be useful for reducing memory/disk used runtime.
     
     The in-memory cache deletion is synchronous and the image is removed immediately.
     
     The possible disk file deletion operation will be asynchronous and it will be performed when possible.
     
     - parameter url: url for the image to remove
     - parameter removeFromDisk: whether to remove from disk also.
     */
    public func removeImage(url url: String, removeFromDisk: Bool) {
        lock.withWriteLock {
            self.inMemoryCache.removeValueForKey(url)
        }
        
        if removeFromDisk {
            dispatch_async(diskOperationQueue) {
                do {
                    let filePath = self.getFilePath(url: url)

                    if self.fileManager.fileExistsAtPath(filePath) {
                        try self.fileManager.removeItemAtPath(filePath)
                    }
                } catch let error {
                    log.error("Failed to remove file on disk, error: \(error)")
                }
            }
        }
    }
    
    /**
     Inserts a new image into the cache, either only to the in-memory cache or on disk as well. 
     
     This can be useful for pre-loaded images, images scaled on-the-fly (in which case you could use a 
     randomized UUID string as the 'url') or local-only images (in which case you could use the asset url
     or a randomized UUID string as the 'url').

     NOTE that this overload cannot be used to stored GIF images properly. Use the NSData overload instead.
     
     The in-memory cache insertion is synchronous and the image is available immediately.
     
     The possible disk write operation will be asynchronous and it will be available when possible.
     
     - parameter image: image to place to the cache
     - parameter url: URL of the image
     - parameter storeOnDisk: whether to store the image to the disk cache also.
     */
    public func putImage(image originalImage: UIImage, url: String, storeOnDisk: Bool) {
        if url.lowercaseString.hasSuffix(gifExtension) {
            log.warning("putImage() called with .gif extension; this method cannot be used to properly store gifs.")
        }
        
        var imageToStore = originalImage
        
        if let maximumImageDimensions = self.maximumImageDimensions {
            log.verbose("Downscaling the downloaded image to max size: \(maximumImageDimensions)")
            imageToStore = originalImage.scaleDown(maxSize: maximumImageDimensions)
        }

        insertToMemoryCache(image: imageToStore, url: url)
        
        if storeOnDisk {
            encodeAndWriteImageToDisk(image: imageToStore, filePath: getFilePath(url: url))
        }
    }
    
    /**
     Stores image data to the disk cache without re-encoding. Also, no downscaling is applied.
     
     The disk write operation will be asynchronous and it will be available when possible.
     
     - parameter imageData: image bytes to store
     - parameter url: URL of the image
     */
    public func storeImage(imageData data: NSData, url: String) {
        dispatch_async(diskOperationQueue) {
            let filePath = self.getFilePath(url: url)
            
            do {
                try self.fileManager.removeItemAtPath(filePath) // First remove the file if it exists
            } catch {
                // Not found, can ignore
            }
            
            data.writeToFile(filePath, atomically: true)
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
    @available(*, deprecated, message="use the other overload instead. this will be removed in a (near) future release.")
    public func getImage(url url: String, fetch: Bool = true) -> UIImage? {
        return getImage(url: url, loadPolicy: fetch ? .Network : .Disk)
    }

    /// Where to look for an image being loaded from the cache.
    public enum CacheLoadPolicy {
        /// Look for the image only in the in-memory cache
        case Memory
        /// Look for the image in in-memory cache and if not found, on the disk
        case Disk
        /// Look for the image over the network if not found in in-memory cache or on the disk
        case Network
    }
    
    /**
     Returns an image matching the given token from the cache. If not found, returns nil.
     Only in-memory cache is accessed synchronously; if the image is loaded from disk or retrieved over the
     internet, this is done asynchronously. When asynchronous load succeeds,
     cacheImageLoadedNotification is sent with urlParam set.
     
     If asynchronous load fails, cacheImageLoadFailedNotification is sent, with urlParam set.

     - parameter url: image URL to request
     - parameter loadPolicy: whether to look for the image only in in-memory cache, or also on disk and/or over network.
    */
    public func getImage(url url: String, loadPolicy: CacheLoadPolicy) -> UIImage? {
        log.verbose("getting image for url: \(url)")
        
        // Check if the image is found in the in-memory cache
        let image = lock.withReadLock {
            return self.inMemoryCache[url]
        }
        
        if image != nil {
            log.verbose("Image found in in-memory cache.")
            return image
        }

        if loadPolicy == .Memory {
            // Image not found in in-memory cache and we won't be looking any further!
            return nil
        }
        
        dispatch_async(diskOperationQueue) {
            let filePath = self.getFilePath(url: url)

            var image: UIImage?
            
            if url.lowercaseString.hasSuffix(gifExtension) {
                // GIFs are handled differently
                log.verbose("Loading a GIF image")
                if let gifData = NSData(contentsOfFile: filePath) {
                    image = UIImage.gifWithData(gifData)
                }
            } else {
                log.verbose("Loading a standard (JPEG/PNG) image")
                image = UIImage(contentsOfFile: filePath)
            }
            
            if let image = image {
                // Image found in disk cache; 'touch' the file to update its timestamp
                log.verbose("Image found on disk in path \(filePath)")
                do {
                    try self.fileManager.setAttributes([NSFileModificationDate: NSDate()], ofItemAtPath: filePath)
                } catch let error {
                    log.error("Failed to update last modification date of file \(filePath), error: \(error)")
                }
                
                self.insertToMemoryCache(image: image, url: url) // Will send loaded -notification
            } else {
                log.verbose("Image not found on disk.")
                if loadPolicy == .Network {
                    if self.downloadManager.hasPendingDownload(url: url) {
                        log.verbose("Already fetching image from url \(url)")
                    } else {
                        self.fetchImage(url: url)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Whether an image for a given URL is present in the in-memory cache
    public func availableInMemory(url url: String) -> Bool {
        let image = lock.withReadLock {
            return self.inMemoryCache[url]
        }
        
        return image != nil
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
        diskOperationQueue = dispatch_queue_create("fi.qvik.ImageCache-\(imagePath ?? "default")", DISPATCH_QUEUE_SERIAL)
            
        super.init()
        
        log.verbose("My disk cache path is: \(path)")
        
        checkCacheDirExists()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ImageCache.memoryWarningNotification(_:)), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        
        reapDiskCache()
    }
}
