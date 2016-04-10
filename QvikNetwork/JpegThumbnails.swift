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

// Helpful links for parsing JPEG/JFIF:s
// - http://sqlanywhere.blogspot.fi/2008/12/jpeg-width-and-height.html
// - https://en.wikipedia.org/wiki/JPEG
// - https://en.wikipedia.org/wiki/JPEG_File_Interchange_Format
//
// Also check out facebook's post about the very same thing
// - https://code.facebook.com/posts/991252547593574


// The following format is used for the thumbnail data: 
//
//  Offset | Length (bytes) | Content
// --------+----------------+------------------------------------------------
//    0    |        1       | Version of dataformat; currently, 1
//    1    |        1       | Type of the image data
//    2    |        1       | Width of the thumbnail
//    3    |        1       | Height of the thumbnail
//    4    |        n       | image data

// JPEG header constants
private let jpegMarkerByte: UInt8 = 0xFF
private let jpegEOIMarker: UInt8 = 0xD9 // End of image
private let jpegSOSMarker: UInt8 = 0xDA // Start of Scan
private let jpegSOF0Marker: UInt8 = 0xC0 // Start of Frame (baseline DCT-based JPEG)
private let jpegEOI = [jpegMarkerByte, jpegEOIMarker]

// Thumbnail packet constants
private let thumbHeaderPacketVersion: UInt8 = 0x01
private let thumbHeaderLength: Int = 4
private let thumbHeaderIndexVersion = 0
private let thumbHeaderIndexDataType = 1
private let thumbHeaderIndexImageWidth = 2
private let thumbHeaderIndexImageHeight = 3

/// Map of registered custom data type -> JPEG header pairs.
private var headerMap = [UInt8: NSData]()

/// Finds the (next) index of a give marker; returns index of the FF marker byte; the actual
/// marker content (if any) begins at this index + 2 bytes.
private func findMarker(marker: UInt8, startIndex: Int, data: UnsafePointer<UInt8>, dataLength: Int) -> Int? {
    var index = startIndex
    var previousByte: UInt8? = nil
    
    while index < dataLength {
        let currentByte = data[index]
        
        if let previousByte = previousByte where previousByte == jpegMarkerByte {
            if currentByte == marker {
                // Requested marker found; return the index of the marker byte FF
                return index - 1
            }
        }

        previousByte = currentByte
        index += 1
    }
    
    return nil
}

/// Writes the given image dimensions into the JPEG header in the given data. Returns true if successful
private func writeImageSize(jpegData jpegData: NSData, imageWidth: UInt8, imageHeight: UInt8) -> Bool {
    let bytes = UnsafeMutablePointer<UInt8>(jpegData.bytes)
    
    guard let sofIndex = findMarker(jpegSOF0Marker, startIndex: 0, data: bytes, dataLength: jpegData.length) else {
        log.error("Failed to locate SOF0 marker in JPEG data!")
        return false
    }

    // SOF0 marker contents are: len(2bytes), numChannels(1byte), height(2bytes), width(2bytes)
    // eg. FF C0 00 11 08 00 1C 00 2A .. 0011 = len, 08 = numChannels, 001C = height, 002A = width
    bytes[sofIndex + 5] = 0
    bytes[sofIndex + 6] = imageHeight
    bytes[sofIndex + 7] = 0
    bytes[sofIndex + 8] = imageWidth
    
    return true
}

/// Returns JPEG image data out of a complete JPEG data, omitting any 'headers' including end of image marker.
private func extractJpegImageData(jpegData: NSData) -> NSData? {
    let bytes = UnsafePointer<UInt8>(jpegData.bytes)
    
    // Locate the Start of Scan (image data) marker
    guard let sosIndex = findMarker(jpegSOSMarker, startIndex: 0, data: bytes, dataLength: jpegData.length) else {
        log.error("Failed to find SOS marker in JPEG data!")
        return nil
    }
    
    // Locate the End of Image marker
    guard let eoiIndex = findMarker(jpegEOIMarker, startIndex: sosIndex, data: bytes, dataLength: jpegData.length) else {
        log.error("Failed to find EOI marker in JPEG data!")
        return nil
    }
    
    // JPEG data exists between end of SOS marker and the beginning of EOI marker
    let imageDataStartIndex = sosIndex + 2
    let imageDataLength = eoiIndex - imageDataStartIndex
    log.debug("imageDataStartIndex = \(imageDataStartIndex), imageDataLength: \(imageDataLength)")
    let imageDataPointer = UnsafeMutablePointer<UInt8>(bytes.advancedBy(imageDataStartIndex))
    
    return NSData(bytesNoCopy: imageDataPointer, length: imageDataLength, freeWhenDone: false)
}

/**
 Registers a new data type -> JPEG header mapping. This will be cached in-memory.
 
 If needed, this can also be used to override the standard iOS header (data type: thumbHeaderDataTypeIOSJPEG).
 
 - parameter dataType: data type value corresponding to the thumbnail data packets
 - parameter headerData: JPEG header to use for this data type value
*/
public func registerJpegThumbnailHeader(dataType dataType: UInt8, headerData: NSData) {
    headerMap[dataType] = headerData
}

/**
 Creates a base64 string representing the JPEG data (excluding the header and EOI - end of image - marker). 

 As this method internally uses UIImageJPEGRepresentation(), you might want to consider wrapping the function call
 inside autorelease pool: ```autoreleasepool { imageToJpegThumbnailData( .. ) }```.
 
 Max dimensions for the thumbnail are 256x256, although you should aim for something like 
 42x42 (see ```pixelBudget``` param.)
 
 - parameter sourceImage: source UIImage
 - parameter dataType: data type value for this data; should be the constant indicating iOS JPEG encoder.
 - parameter compressionQuality: compression quality [0..1] to use for the JPEG. Should be around 0.2 - 0.3.
 - parameter pixelBudget: approximate amount of pixels in the thumbnail.
 - returns: the data representing the thumbnail (our custom header + JPEG data) if successful
*/
public func imageToJpegThumbnailData(sourceImage image: UIImage, dataType: UInt8, compressionQuality: CGFloat, pixelBudget: Int = (42 * 42)) -> NSData? {
    // Calculate the thumbnail size by comparing amount of pixels in original image to the 
    // 'pixel budget' while retaining the aspect ratio
    let imageWidth = floor(image.width * image.scale)
    let imageHeight = floor(image.height * image.scale)
    let numPixels = imageWidth * imageHeight
    let ratio = sqrt(CGFloat(pixelBudget) / numPixels)
    let thumbWidth = round(ratio * imageWidth)
    let thumbHeight = round(ratio * imageHeight)
    
    log.verbose("Creating JPEG thumbnail with dimensions \(thumbWidth) x \(thumbHeight)")
    
    if (thumbWidth > 255) || (thumbHeight > 255) {
        log.error("Thumbnail resulted dimensions larger than 255x255!")
        return nil
    }
    
    // Create a scaled-down thumbnail image and encode it into a baseline DCT-based JPEG
    let thumbnail = image.scaleTo(size: CGSize(width: thumbWidth, height: thumbHeight))
    guard let jpegData = UIImageJPEGRepresentation(thumbnail, compressionQuality) else {
        log.error("Failed to encode thumbnail JPEG")
        return nil
    }

    //TODO REMOVE
//    let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
//    let jpegPath = (documentsPath as NSString).stringByAppendingPathComponent("thumbnail.jpeg")
//    if jpegData.writeToFile(jpegPath, atomically: true) {
//        log.debug("JPEG thumb written to \(jpegPath)")
//    } else {
//        log.error("Failed to write JPEG")
//    }
    
    // Try to extract the JPEG image data
    guard let jpegImageData = extractJpegImageData(jpegData) else {
        log.error("Failed to extract image data from the JPEG data")
        return nil
    }

    // Create the thumbnail data packet; for format, see the start of this file.
    // Packet length is our header length + image data length
    guard let packetData = NSMutableData(capacity: thumbHeaderLength + jpegImageData.length) else {
        log.error("Failed to allocate memory for the packet")
        return nil
    }

    let thumbHeader = [thumbHeaderPacketVersion, dataType, UInt8(thumbWidth), UInt8(thumbHeight)]
    packetData.appendBytes(UnsafePointer<UInt8>(thumbHeader), length: thumbHeader.count)
    packetData.appendData(jpegImageData)

    log.verbose("JPEG thumb packet is \(packetData.length) bytes")
    
    return packetData
}

/**
 Creates an image out of given thumbnail image data packet (for format, see the start of this source file).
 
 This method could be somewhat CPU intense so you might consider running it in a non-UI thread.
 
 - parameter data: thumbnail packet data
 - parameter maxSize: Max dimensions to scale the image to, retaining aspect ratio.
 - parameter imageScale: value for result image's UIImage.scale. Specify 0.0 to match the scale of the device's screen.
 - returns: Scaled-up and blurred version of the thumbnail, if successful
*/
public func jpegThumbnailDataToImage(data data: NSData, maxSize: CGSize, thumbnailBlurRadius: Double = 3.0, imageScale: CGFloat = 0.0) -> UIImage? {
    let ptr = UnsafeMutablePointer<UInt8>(data.bytes)
    if ptr[thumbHeaderIndexVersion] != thumbHeaderPacketVersion {
        log.error("Version mismatch!")
        return nil
    }
    
    let thumbWidth = ptr[thumbHeaderIndexImageWidth]
    let thumbHeight = ptr[thumbHeaderIndexImageHeight]
//    log.debug("Thumbnail size: \(thumbWidth) x \(thumbHeight)")
    
    // Get the JPEG header data for this data type
    guard let jpegHeaderData = headerMap[ptr[thumbHeaderIndexDataType]] else {
        log.error("Could not find JPEG header data")
        return nil
    }
//    log.debug("Read \(jpegHeaderData.length) bytes of JPEG header")
    
    guard let jpegData = NSMutableData(capacity: (jpegHeaderData.length + (data.length - thumbHeaderLength) + jpegEOI.count)) else {
        log.error("Failed to allocate memory for JPEG data!")
        return nil
    }

    // Construct a whole JPEG from a predefined header block, the jpeg data and EOI marker (2 bytes)
    jpegData.appendData(jpegHeaderData)
    jpegData.appendBytes(UnsafePointer<UInt8>(data.bytes).advancedBy(thumbHeaderLength), length: (data.length - thumbHeaderLength))
    jpegData.appendBytes(UnsafePointer<UInt8>(jpegEOI), length: jpegEOI.count)
    
    // Patch in the thumbnail size into the copied header to get an result image of the correct size
    if !writeImageSize(jpegData: jpegData, imageWidth: thumbWidth, imageHeight: thumbHeight) {
        log.error("Failed to write thumbnail dimensions to JPEG header!")
        return nil
    }
    
    // Create an UIImage out of this JPEG data
    guard let thumbnailImage = UIImage(data: jpegData) else {
        log.error("Failed to create UIImage from JPEG data!")
        return nil
    }

    // Scale the image up to match the requested max size
    let scaledThumbnail = thumbnailImage.scaleToFit(sizeToFit: maxSize, imageScale: imageScale)

    // Blur the image
    let blurredThumbnail = scaledThumbnail.blur(radius: thumbnailBlurRadius, algorithm: .BoxConvolve)
    
    return blurredThumbnail
}

