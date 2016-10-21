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

import QvikSwift
import QvikUi

/**
 An UIImageView that retrieves the image from ImageCache (default shared instance).
 
 If you set ```placeholderImage```, it will be displayed while the main image loads. 

 If you set ```thumbnailData```, the thumbnail will be displayed while the main image loads
 unless ```placeholderImage``` is set.
 
 If you set ```fadeInColor```, it will be displayed while the main image loads, unless 
 ```placeholderImage``` or ```thumbnailData``` are set.
 
 Example setup:
 ```swift
 cachedImageView.imageUrl = myImageDescriptor?.scaledUrl
 cachedImageView.thumbnailData = myImageDescriptor?.thumbnailData
 cachedImageView.thumbnailDominantColor = myImageDescriptor?.dominantColor
 ```
*/
open class CachedImageView: QvikImageView {
    /// Placeholder image view; used to display a temporary image (smaller or thumbnail) while actual image loads
    fileprivate var placeholderImageView: UIImageView? = nil

    /// Duration for fading in the loaded image, in case it is asynchronously loaded.
    open var imageFadeInDuration: TimeInterval = 0.3
    
    /// JPEG thumbnail data for the image. Should set this before layout cycle.
    open var thumbnailData: Data? = nil {
        didSet {
            reset()
            setNeedsLayout()
        }
    }

    /// Dominant color of the image (and thumbnail). If set, will be displayed while thumbnail image is loaded.
    open var thumbnailDominantColor: UIColor? = nil

    /// Preview thumbnail blur radius (size of the convolution kernel)
    open var thumbnailBlurRadius = 7.0

    /// Whether caching thumbnail images is enabled. Disable for less memory usage but poorer reuse performance.
    open var enableThumbnailCaching = true

    /// Fade-in timeout for the thumbnail in case it was loaded asynchronously, in seconds.
    open var thumbnailFadeInDuration: TimeInterval = 0.1 {
        didSet {
            assert(thumbnailFadeInDuration >= 0.0, "Must not use a negative value!")
        }
    }

    /// Color for a fade-in view; used in case ```thumbnailData``` is not set
    @IBInspectable
    open var fadeInColor: UIColor? = nil {
        didSet {
            reset()
            setNeedsLayout()
        }
    }

    /// Placeholder image; displayed while actual image loads.
    open var placeholderImage: UIImage? = nil {
        didSet {
            reset()
            setNeedsLayout()
        }
    }

    /// ImageCache instance to use. Default value is the shared instance.
    open var imageCache = ImageCache.default
    
    /// Callback to be called when the image changes.
    open var imageChangedCallback: ((Void) -> Void)?
    
    /// Whether to automaticallty respond to image load notification
    open var ignoreLoadNotification = false
    
    override open var image: UIImage? {
        didSet {
            imageChangedCallback?()
        }
    }
    
    /// Image URL. Setting this will cause the view to automatically load the image
    open var imageUrl: String? = nil {
        didSet {
            assert(Thread.isMainThread, "Must be called on main thread!")

            reset()
            setNeedsLayout()
            
            if let imageUrl = imageUrl, imageUrl.length > 0 {
                if imageUrl == oldValue {
                    // No need to do anything
                    return
                }
                
                self.image = imageCache.getImage(url: imageUrl, loadPolicy: .network)
            } else {
                self.image = nil
            }
        }
    }

    /// Load the thumbnail image from either in-memory cache or from the JPEG data.
    fileprivate func loadThumbnail(fromData: Data, completionCallback: @escaping ((_ thumbnail: UIImage?, _ async: Bool) -> Void)) {
        var md5: String? = nil

        if enableThumbnailCaching {
            md5 = self.thumbnailData?.md5().toHexString()
            guard let md5 = md5 else {
                log.error("Failed to calculate md5 string out of thumb data!")
                completionCallback(nil, false)
                return
            }

            // Check if the image is present in in-memory cache
            if let thumbImage = ImageCache.default.getImage(url: md5, loadPolicy: .memory) {
                completionCallback(thumbImage, false)
                return
            }
        }

        // Not in cache; load asynchronously
        runInBackground {
            let thumbImage = jpegThumbnailDataToImage(data: fromData, maxSize: self.frame.size, thumbnailBlurRadius: self.thumbnailBlurRadius)

            if let thumbImage = thumbImage, self.enableThumbnailCaching {
                // Put into in-memory cache
                ImageCache.default.putImage(image: thumbImage, url: md5!, storeOnDisk: false)
            }

            runOnMainThread {
                completionCallback(thumbImage, true)
            }
        }
    }

    /// Resets all the properties (extra views etc) to the original state
    fileprivate func reset() {
        placeholderImageView?.removeFromSuperview()
        placeholderImageView = nil
    }

    /**
     The image for this image view has been loaded into the in-memory cache and is available
     for use. The default behavior is to set the image object property from the cache for display.
     
     Extending classes may override this to change the default behavior.
     */
    open func imageLoaded() {
        if let imageUrl = self.imageUrl {
            if let image = ImageCache.default.getImage(url: imageUrl, loadPolicy: .memory) {
                // Image loaded & found
                self.image = image
                
                // Fade out the thumbnail view
                UIView.animate(withDuration: imageFadeInDuration, animations: {
                    self.placeholderImageView?.alpha = 0.0
                    }, completion: { finished in
                        // Remove placeholder views to save memory
                        self.reset()
                })
            }
        }
    }
    
    func imageLoadedNotification(_ notification: Notification) {
        assert(Thread.isMainThread, "Must be called on main thread!")
        
        if ignoreLoadNotification {
            return
        }
        
        if let imageUrl = (notification as NSNotification).userInfo?[ImageCache.urlParam] as? String {
            if imageUrl == self.imageUrl {
                imageLoaded()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        
        if image == nil {
            // No image yet; show a placeholder / thumbnail image if present
            if let placeholderImage = placeholderImage {
                if placeholderImageView == nil {
                    placeholderImageView = UIImageView(frame: self.bounds)
                    placeholderImageView!.contentMode = self.contentMode
                    placeholderImageView!.image = placeholderImage
                    insertSubview(placeholderImageView!, at: 0)
                }
            } else if let thumbnailData = thumbnailData {
                if placeholderImageView == nil {
                    placeholderImageView = UIImageView(frame: self.bounds)
                    placeholderImageView!.contentMode = self.contentMode

                    let backgroundColor = thumbnailDominantColor ?? (fadeInColor ?? UIColor.white)
                    placeholderImageView?.backgroundColor = backgroundColor

                    loadThumbnail(fromData: thumbnailData) { (thumbnailImage, async) in
                        self.placeholderImageView?.image = thumbnailImage

                        if async {
                            // Fade in the thumbnail 
                            self.placeholderImageView?.alpha = 0
                            UIView.animate(withDuration: self.thumbnailFadeInDuration, animations: {
                                self.placeholderImageView?.alpha = 1
                                }, completion: { finished in

                            })
                        }
                    }

                    insertSubview(placeholderImageView!, at: 0)
                }
            } else if let fadeInColor = fadeInColor, placeholderImageView == nil {
                // No placeholderImage/thumbnailData data set; show a colored fade-in view
                if placeholderImageView == nil {
                    placeholderImageView = UIImageView(frame: self.bounds)
                    placeholderImageView!.backgroundColor = fadeInColor
                    insertSubview(placeholderImageView!, at: 0)
                }
            }
        }

        placeholderImageView?.frame = self.frame
    }

    fileprivate func commonInit() {
        NotificationCenter.default.addObserver(self, selector: #selector(imageLoadedNotification), name: NSNotification.Name(rawValue: ImageCache.cacheImageLoadedNotification), object: nil)
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        
        commonInit()
    }
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        
        commonInit()
    }
}
