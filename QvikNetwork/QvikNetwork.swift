//
//  QvikNetwork.swift
//  QvikNetwork
//
//  Created by Matti Dahlbom on 27/09/15.
//  Copyright © 2015 Qvik. All rights reserved.
//

import Foundation
import XCGLogger

let log = QvikNetwork.createLogger()

public class QvikNetwork {
    private static func createLogger() -> XCGLogger {
        let log = XCGLogger.defaultInstance()
        log.setup(.Info, showLogLevel: true, showFileNames: true, showLineNumbers: true, writeToFile: nil, fileLogLevel: nil)
        
        return log
    }
    
    public static var debugLogging = false {
        didSet {
            if debugLogging {
                log.setup(.Debug, showLogLevel: true, showFileNames: true, showLineNumbers: true, writeToFile: nil, fileLogLevel: nil)
            } else {
                log.setup(.Info, showLogLevel: true, showFileNames: true, showLineNumbers: true, writeToFile: nil, fileLogLevel: nil)
            }
        }
    }
}
