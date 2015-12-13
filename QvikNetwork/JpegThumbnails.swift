//
//  JpegThumbnails.swift
//  QvikNetwork
//
//  Created by Matti Dahlbom on 13/12/15.
//  Copyright © 2015 Qvik. All rights reserved.
//

import UIKit
import QvikSwift

// The following format is used for the thumbnail data: 
//
//  Offset | Length (bytes) | Content
// --------+----------------+------------------------------------------------
//    0    |        1       | Version of dataformat; currently, 1
//    1    |        1       | Width of the thumbnail
//    2    |        1       | Height of the thumbnail
//    3    |        n       | JPEG image data without header (contents of SOS marker)

// JPEG header constants
private let jpegMarkerByte: UInt8 = 0xFF
private let jpegEOIMarker: UInt8 = 0xD9 // End of image
private let jpegSOSMarker: UInt8 = 0xDA // Start of Scan
private let jpegSOF0Marker: UInt8 = 0xC0 // Start of Frame (baseline DCT-based JPEG)

// Current thumbnail packet header version
private let headerPacketVersion: UInt8 = 0x01

/// Returns the JPEG header data, reading it from bundle if not already in memory
private func getJpegHeader() -> NSData {
    struct Static {
        static var jpegHeaderData: NSData? = nil // Constant, predefined JPEG header data
        static var onceToken: dispatch_once_t = 0
    }
    
    dispatch_once(&Static.onceToken) {
        guard let filePath = NSBundle.mainBundle().pathForResource("jpegheader", ofType: "data") else {
            log.error("Missing 'jpegheader.data' in bundle!")
            return
        }
        Static.jpegHeaderData = NSData(contentsOfFile: filePath)
    }

    return Static.jpegHeaderData!
}

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
        index++
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
    log.debug("sosIndex = \(sosIndex)")
    
    // Locate the End of Image marker
    guard let eoiIndex = findMarker(jpegEOIMarker, startIndex: sosIndex, data: bytes, dataLength: jpegData.length) else {
        log.error("Failed to find EOI marker in JPEG data!")
        return nil
    }
    log.debug("eoiIndex = \(eoiIndex)")
    
    // JPEG data exists between end of SOS marker and the beginning of EOI marker
    let imageDataStartIndex = sosIndex + 2
    let imageDataLength = eoiIndex - imageDataStartIndex
    let imageDataPointer = UnsafeMutablePointer<Void>(bytes.advancedBy(imageDataStartIndex))
    log.debug("imageDataStartIndex = \(imageDataStartIndex), imageDataLength = \(imageDataLength)")
    
    return NSData(bytesNoCopy: imageDataPointer, length: imageDataLength, freeWhenDone: false)
}

/**
 Creates a base64 string representing the JPEG data (excluding the header and EOI - end of image - marker). 

 As this method internally uses UIImageJPEGRepresentation(), you might want to consider wrapping the function call
 inside autorelease pool: ```autoreleasepool { createJpegThumbnailData( .. ) }```.
 
 Max dimensions for the thumbnail are 256x256, although you should aim for something like 
 42x42 (see ```pixelBudget``` param.)
 
 - parameter sourceImage: source UIImage
 - parameter pixelBudget: approximate amount of pixels in the thumbnail.
 - returns: the data representing the thumbnail (JPEG data + 3 bytes of our custom header) if successful
*/
public func imageToJpegThumbnailData(sourceImage image: UIImage, pixelBudget: Int = (42 * 42)) -> NSData? {
    // Calculate the thumbnail size by comparing amount of pixels in original image to the 
    // 'pixel budget' while retaining the aspect ratio
    let imageWidth = floor(image.width * image.scale)
    let imageHeight = floor(image.height * image.scale)
    let numPixels = imageWidth * imageHeight
    let ratio = sqrt(CGFloat(pixelBudget) / numPixels)
    let thumbWidth = round(ratio * imageWidth)
    let thumbHeight = round(ratio * imageHeight)
    log.debug("image size: \(Int(imageWidth)) x \(Int(imageHeight)), thumb size: \(Int(thumbWidth)) x \(Int(thumbHeight))")
    
    if (thumbWidth > 255) || (thumbHeight > 255) {
        log.error("Thumbnail resulted dimensions larger than 255x255!")
        return nil
    }
    
    // Create a scaled-down thumbnail image and encode it into a baseline DCT-based JPEG
    let thumbnail = image.scale(scaledSize: CGSize(width: thumbWidth, height: thumbHeight))
    guard let jpegData = UIImageJPEGRepresentation(thumbnail, 0.2) else {
        log.error("Failed to encode thumbnail JPEG")
        return nil
    }
    log.debug("JPEG total data length: \(jpegData.length)")
    
    //TODO remove : write thumbnail file to disk
    let docDir = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first!
    let thumbPath = (docDir as NSString).stringByAppendingPathComponent("thumbnail.jpg")
    jpegData.writeToFile(thumbPath, atomically: true)
    log.debug("JPEG data written to file: \(thumbPath)")

    // Try to extract the JPEG image data
    guard let jpegImageData = extractJpegImageData(jpegData) else {
        log.error("Failed to extract image data from the JPEG data")
        return nil
    }
    log.debug("JPEG image data length: \(jpegImageData.length)")

    //TODO remove: write thumbnail data file to disk
    let thumbDataPath = (docDir as NSString).stringByAppendingPathComponent("thumbnail.data")
    jpegImageData.writeToFile(thumbDataPath, atomically: true)
    log.debug("JPEG data written to file: \(thumbDataPath)")

    // Create the thumbnail data packet; for format, see the start of this file.
    // Packet length is our header length (3) + image data length
    guard let packetData = NSMutableData(capacity: 3 + jpegImageData.length) else {
        log.error("Failed to allocate memory for the packet")
        return nil
    }
    
    let thumbHeader = [headerPacketVersion, UInt8(thumbWidth), UInt8(thumbHeight)]
    packetData.appendBytes(UnsafePointer<Void>(thumbHeader), length: 3)
    packetData.appendData(jpegImageData)
    log.debug("packetData.length = \(packetData.length)")
    
    return packetData
}

/**
 Creates an image out of given thumbnail image data packet (for format, see the start of this source file).
 
 - parameter data: thumbnail packet data
 - parameter maxSize: Max dimensions to scale the image to, retaining aspect ratio.
 - returns: Scaled-up and blurred version of the thumbnail, if successful
*/
public func jpegThumbnailDataToImage(data data: NSData, maxSize: CGSize) -> UIImage? {
    log.debug("** creating image from thumbnail **")
    
    let ptr = UnsafeMutablePointer<UInt8>(data.bytes)
    if ptr[0] != headerPacketVersion {
        log.error("Version mismatch!")
        return nil
    }
    
    let thumbWidth = ptr[1]
    let thumbHeight = ptr[2]
    let jpegDataPtr = UnsafePointer<UInt8>(data.bytes)
    log.debug("Read thumb size from packet: \(thumbWidth) x \(thumbHeight)")
    
    // Construct a whole JPEG from a predefined header block, the jpeg data and EOI marker (2 bytes)
    let jpegHeaderData = getJpegHeader()
    log.debug("Read \(jpegHeaderData.length) bytes of JPEG header")
    guard let jpegData = NSMutableData(capacity: (jpegHeaderData.length + (data.length - 3) + 2)) else {
        log.error("Failed to allocate memory for JPEG data!")
        return nil
    }
    
    let eoiMarker = [jpegMarkerByte, jpegEOIMarker]
    jpegData.appendData(jpegHeaderData)
    jpegData.appendBytes(jpegDataPtr.advancedBy(3), length: (data.length - 3))
    jpegData.appendBytes(UnsafePointer<Void>(eoiMarker), length: 2)
    log.debug("jpegData.length = \(jpegData.length)")
    
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
    log.debug("Thumbnail image constructed with size: \(thumbnailImage.size)")

    //TODO remove: write jpeg image file
    let docDir = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first!
    let thumbPath = (docDir as NSString).stringByAppendingPathComponent("constructed-thumbnail.jpg")
    jpegData.writeToFile(thumbPath, atomically: true)
    log.debug("Constructed JPEG data written to file: \(thumbPath)")

    //TODO
    let blurredImage = thumbnailImage
    
    return blurredImage
}

