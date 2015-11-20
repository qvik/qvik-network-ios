# Qvik's network utility collection

*This library contains Swift (2.0+) networking utilities for use in both Qvik's internal and customer projects. They are released with the MIT license.*


## Changelog

* 0.0.12 
    * Added .NetworkTimeout support
* 0.0.11
    * Added missing response parsing for non-200 responses
* 0.0.10
    * Changes for changed CryptoSwift API compliance
* 0.0.9
    * New features to CachedImageView
* 0.0.8
    * Added autoreleasepool {} to control memory usage with writing image data
* 0.0.7 
    * Using a dedicated logger instance instead of default (shared) one
    * Performance increase to image cache; added data passthrough writes when applicable
    * Made the ImageCache instance configurable for CachedImageView
* 0.0.6
    * Made CachedImageView inherit from QvikImageView
* 0.0.5
    * Added image changed -callback to CachedImageView
* 0.0.4 
	* Added BaseRemoteService
* 0.0.3
	* Initial version

## Usage

To use the library in your projects, add the following (or what ever suits your needs) to your Podfile:

```ruby
use_frameworks!
source 'https://git.qvik.fi/pods/QvikPodSpecs.git'

pod 'QvikNetwork'
```

And the following to your source:

```ruby
import QvikNetwork
```

## Controlling the library's log level

The library may emit logging for errors, and if you tell it to, debug stuff. Enable debug logging as such:

```swift
QvikNetwork.debugLogging = true
```

## Features

This chapter introduces the library's classes.

### DownloadManager

The purpose of *DownloadManager* (and the related classes *DownloadGroup* and *Download*) is to provide easy-to-use API for downloading files over HTTP(S), typically dynamic application resources such as images and data files. *DownloadManager* also provides a way of grouping downloads together for tracking the overall download progress instead of adding this code
to the application logic. Downloading multiple items at once is common feature in modern mobile applications. *DownloadManager* and the related classes are thread safe.

Example usage:

```swift
let downloadUrls = ["http://example.com/1", "http://example.com/2", "http://example.com/3"]
let downloadManager = DownloadManager.sharedInstance()
let downloadGroup = downloadManager.createGroup()

downloadGroup.progressCallback = { [weak self] totalBytesRead, progress in
	updateProgressUI(progress)
}

downloadGroup.completionCallback = { [weak self] numErrors in
	log.debug("All downloads completed, \(numErrors) errors")
    updateCompletedUI()
}

for url in downloadUrls {
	let download = downloadGroup.download(url)
    download.progressCallback = { [weak self] bytesRead, totalBytesRead, totalBytesExpectedToRead in
	    let progress = Double(totalBytesRead) / Double(totalBytesExpectedToRead)
    	log.debug("Download progress for url \(url): \(progress)")
    }
}

```

### ImageCache

A very fast, disk-backed in-memory image cache, featuring configurable storage location, file format (JPEG/PNG) and disk storage max age etc. It can also be configured to automatically downscale any downloaded images to a maximum size (retaining aspect ratio) before insertion to the in-memory storage and disk. *ImageCache* is thread safe.

Example usage:

```swift
func imageLoaded(notification: NSNotification) {
	if let imageUrl = notification.userInfo?[ImageCache.urlParam] as? String {
    	// Check if it is my image
		if imageUrl == self.imageUrl {
  	      // Now the image is in the cache - get it 
			let image = ImageCache.sharedInstance().getImage(url: imageUrl, fetch: false)
            // TODO use the image for something
        }
    }
}

// ..

let imageCache = ImageCache.sharedInstance()

NSNotificationCenter.defaultCenter().addObserver(self, selector: "imageLoaded:", name: ImageCache.cacheImageLoadedNotification, object: nil)
        
// This will trigger a fetch over the network if not found in cache
guard let image = imageCache.getImage(url: imageUrl) else {
	log.debug("Requested image not found in in-memory cache; waiting for a load from disk or network")
    // .. wait for imageLoaded() to get called
}

```

### CachedImageView

A UIImageView that is backed up by *ImageCache*; features automatic image retrieval from the cache (and hence from the network if not found locally).

Sample usage:

```swift
@IBOutlet private weak var imageView: CachedImageView!

func populateView(message: Message) {
	// Will automatically trigger load from cache/network and populate the image when done
	imageView.imageUrl = message.imageUrl
}

```

### BaseRemoteService

This is a superclass for a Remote API service built on top of the Alamofire HTTP library. It provides response parsing and wraps all the Alamofire APIs, reducing boiler plate from the actual implementation. For full feature set, see the code.

Example implementation:

```swift
class RemoteService: BaseRemoteService {
  private static let singletonInstance = RemoteService()

  class func sharedInstance() -> RemoteService {
    return singletonInstance
  }

  /// Attempts to verify an email address
  func verifyEmailAddress(email: String, completionCallback: (RemoteResponse -> Void)) {
    let url = "\(baseUrl)/api/verifyemail"
    let params = ["email": email]

    request(.POST, url, parameters: params, encoding: .JSON, headers: nil) { response in
      completionCallback(response)
    }
  }

  // TODO Other methods ..

  init() {
    let additionalHeaders = [
      "X-My-API-Key": "asldasdaksdjhakdjhasdkjh",
      "X-My-Api-Version": "1",
      "X-My-Client": getClientId()
    ]

    super.init(backgroundSessionId: "com.example.MyApp", additionalHeaders: additionalHeaders, timeout: 5)
  }
}
```

## Contributing 

Any Swift developer in the company may - and is encouraged to - contribute to this library. Any contributions have to meet the following criteria:

* Meaningfulness. Discuss whether what you are about to contribute indeed belongs to this library in the first place before submitting a pull request.
* Code style. Follow our [Swift style guide](https://github.com/qvik/swift) 100%.
* Stability. No code in the library must ever crash; never place *assert()*s or implicit optional unwrapping in library methods.
* Testing. Create a test app for testing the functionality of your classes.
* Logging. All code in the library must use the common logging handle (see QvikNetwork.swift) and sensible log levels. 

### License

The library is distributed with the MIT License. Make sure all your source files contain the license header at the start of the file:

```
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
```

### Submit your code

All merges to the **master** branch go through a *Pull Request* and MUST meet the above criteria.

In other words, follow the following procedure to submit your code into the library:

* Clone the library repository
* Create a feature branch for your code
* Code it, clean it up, test it thoroughly
* Make sure all your methods meant to be public are defined as public
* Push your branch
* Create a pull request

## Updating the pod

As a contributor you do not need to do this; we'll update the pod whenever needed by projects.

* Update QvikNetwork.podspec and set s.version to match the upcoming tag
* Commit all your changes, merge all pending accepted *Pull Requests*
* Create a new tag following [Semantic Versioning](http://semver.org/); eg. `git tag -a 1.2.0 -m "Your tag comment"`
* `git push --tags`
* `pod repo push QvikPodSpecs QvikNetwork.podspec`

Unless already set up, you might do the following steps to set up the pod repo:

* ```pod repo add QvikPodSpecs https://git.qvik.fi/pods/QvikPodSpecs.git```

## Contact

Any questions? Contact Matti.