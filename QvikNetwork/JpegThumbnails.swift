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
private var headerMap = [UInt8: Data]()

/**
 Registers a new data type -> JPEG header mapping. This will be cached in-memory.

 If needed, this can also be used to override the standard iOS header (data type: thumbHeaderDataTypeIOSJPEG).

 - parameter dataType: data type value corresponding to the thumbnail data packets
 - parameter headerData: JPEG header to use for this data type value
 */
public func registerJpegThumbnailHeader(_ dataType: UInt8, headerData: Data) {
    headerMap[dataType] = headerData
}

/// Finds the (next) index of a give marker; returns index of the FF marker byte; the actual
/// marker content (if any) begins at this index + 2 bytes.
private func findMarker(_ marker: UInt8, startIndex: Int, data: UnsafePointer<UInt8>, dataLength: Int) -> Int? {
    var index = startIndex
    var previousByte: UInt8? = nil
    
    while index < dataLength {
        let currentByte = data[index]
        
        if let previousByte = previousByte, previousByte == jpegMarkerByte {
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
private func writeImageSize(_ jpegData: Data, imageWidth: UInt8, imageHeight: UInt8) -> Bool {
    let bytes = UnsafeMutablePointer<UInt8>(mutating: (jpegData as NSData).bytes.bindMemory(to: UInt8.self, capacity: jpegData.count))
    
    guard let sofIndex = findMarker(jpegSOF0Marker, startIndex: 0, data: bytes, dataLength: jpegData.count) else {
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

/**
 Creates an image out of given thumbnail image data packet (for format, see the start of this source file).
 
 This method could be somewhat CPU intense so you might consider running it in a non-UI thread.
 
 - parameter data: thumbnail packet data
 - parameter maxSize: Max dimensions to scale the image to, retaining aspect ratio.
 - parameter imageScale: value for result image's UIImage.scale. Specify 0.0 to match the scale of the device's screen.
 - returns: Scaled-up and blurred version of the thumbnail, if successful
*/
public func jpegThumbnailDataToImage(_ data: Data, maxSize: CGSize, thumbnailBlurRadius: Double = 3.0, imageScale: CGFloat = 0.0) -> UIImage? {
    let ptr = UnsafeMutablePointer<UInt8>(mutating: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count))
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
    
    guard let jpegData = NSMutableData(capacity: (jpegHeaderData.count + (data.count - thumbHeaderLength) + jpegEOI.count)) else {
        log.error("Failed to allocate memory for JPEG data!")
        return nil
    }

    // Construct a whole JPEG from a predefined header block, the jpeg data and EOI marker (2 bytes)
    jpegData.append(jpegHeaderData)
    jpegData.append((data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count).advanced(by: thumbHeaderLength), length: (data.count - thumbHeaderLength))
    jpegData.append(UnsafePointer<UInt8>(jpegEOI), length: jpegEOI.count)
    
    // Patch in the thumbnail size into the copied header to get an result image of the correct size
    if !writeImageSize(jpegData as Data, imageWidth: thumbWidth, imageHeight: thumbHeight) {
        log.error("Failed to write thumbnail dimensions to JPEG header!")
        return nil
    }
    
    // Create an UIImage out of this JPEG data
    guard let thumbnailImage = UIImage(data: jpegData as Data) else {
        log.error("Failed to create UIImage from JPEG data!")
        return nil
    }

    // Scale the image up to match the requested max size
    let scaledThumbnail = thumbnailImage.scaleToFit(sizeToFit: maxSize, imageScale: imageScale)

    // Blur the image
    let blurredThumbnail = scaledThumbnail.blur(radius: thumbnailBlurRadius, algorithm: .boxConvolve)
    
    return blurredThumbnail
}
