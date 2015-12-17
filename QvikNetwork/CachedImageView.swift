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

/**
An UIImageView that retrieves the image from ImageCache (default shared instance).
*/
@IBDesignable
public class CachedImageView: QvikImageView {
    private var thumbnailImageView: UIImageView? = nil
    private var fadeInView: UIView? = nil
    
    /// Duration for fading in the loaded image, in case it is asynchronously loaded.
    @IBInspectable
    public var imageFadeInDuration: NSTimeInterval = 0.5
    
    /// JPEG thumbnail data for the image. Should set this before layout cycle.
    public var thumbnailData: NSData? = nil
    
    /// Color for a fade-in view; used in case ```thumbnailData``` is not set
    @IBInspectable
    public var fadeInColor: UIColor? = nil
    
    /// ImageCache instance to use. Default value is the shared instance.
    public var imageCache = ImageCache.sharedInstance()
    
    /// Callback to be called when the image changes.
    public var imageChangedCallback: (Void -> Void)?
    
    /// Whether to automaticallty respond to image load notification
    @IBInspectable
    public var ignoreLoadNotification = false
    
    override public var image: UIImage? {
        didSet {
            imageChangedCallback?()
        }
    }
    
    /// Image URL. Setting this will cause the view to automatically load the image
    public var imageUrl: String? = nil {
        didSet {
            assert(NSThread.isMainThread(), "Must be called on main thread!")

            reset()
            
            if imageUrl?.length <= 0 {
                self.image = nil
                return
            }
            
            if let imageUrl = imageUrl {
                if imageUrl == oldValue {
                    // No need to do anything
                    return
                }
                
                self.image = imageCache.getImage(url: imageUrl, fetch: true)
            }
        }
    }

    /// Resets all the properties (extra views etc) to the original state
    private func reset() {
        thumbnailImageView?.removeFromSuperview()
        thumbnailImageView = nil
        fadeInView?.removeFromSuperview()
        fadeInView = nil
    }

    /**
     The image for this image view has been loaded into the in-memory cache and is available
     for use. The default behavior is to set the image object property from the cache for display.
     
     Extending classes may override this to change the default behavior.
     */
    public func imageLoaded() {
        if let imageUrl = self.imageUrl {
            if let image = ImageCache.sharedInstance().getImage(url: imageUrl, fetch: false) {
                // Image loaded & found
                self.image = image
                
                // Fade out the thumbnail view
                UIView.animateWithDuration(imageFadeInDuration, animations: {
                    self.thumbnailImageView?.alpha = 0.0
                    self.fadeInView?.alpha = 0.0
                    }, completion: { finished in
                        self.reset()
                })
            }
        }
    }
    
    func imageLoadedNotification(notification: NSNotification) {
        assert(NSThread.isMainThread(), "Must be called on main thread!")
        
        if ignoreLoadNotification {
            return
        }
        
        if let imageUrl = notification.userInfo?[ImageCache.urlParam] as? String {
            if imageUrl == self.imageUrl {
                imageLoaded()
            }
        }
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        if image == nil {
            // No image yet; show a thumbnail image if present
            if let thumbnailData = thumbnailData {
                if thumbnailImageView == nil {
                    thumbnailImageView = UIImageView(frame: self.frame)
                    thumbnailImageView!.contentMode = self.contentMode
                    thumbnailImageView!.image = jpegThumbnailDataToImage(data: thumbnailData, maxSize: self.frame.size)
                    insertSubview(thumbnailImageView!, atIndex: 0)
                    
                    // Discard thumbnail data to save memory
                    self.thumbnailData = nil
                } else {
                    thumbnailImageView!.frame = self.frame
                }
            } else if let fadeInColor = fadeInColor where thumbnailImageView == nil {
                if fadeInView == nil {
                    // No thumbnail data set; show a colored fade-in view
                    fadeInView = UIView(frame: self.frame)
                    fadeInView!.backgroundColor = fadeInColor
                    insertSubview(fadeInView!, atIndex: 0)
                } else {
                    fadeInView!.frame = self.frame
                }
            }
        }
    }
    
    private func commonInit() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "imageLoadedNotification:", name: ImageCache.cacheImageLoadedNotification, object: nil)
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

