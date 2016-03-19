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

import Foundation
import XCGLogger

let log = QvikNetwork.createLogger()

public class QvikNetwork {
    public enum LogLevel {
        case Info
        case Debug
        case Verbose
    }
    
    private static func createLogger() -> XCGLogger {
        let logger = XCGLogger(identifier: "QvikNetwork")
        logger.setup(.Info, showLogLevel: true, showFileNames: true, showLineNumbers: true, writeToFile: nil, fileLogLevel: nil)
        
        return logger
    }

    @available(*, deprecated, message="use .logLevel instead")
    public static var debugLogging = false {
        didSet {
            QvikNetwork.logLevel = debugLogging ? .Debug : .Info
        }
    }
    
    public static var logLevel = QvikNetwork.LogLevel.Info {
        didSet {
            let level: XCGLogger.LogLevel
            
            switch logLevel {
            case .Info:
                level = .Info
            case .Debug:
                level = .Debug
            case .Verbose:
                level = .Verbose
            }
            
            log.setup(level, showLogLevel: true, showFileNames: true, showLineNumbers: true, writeToFile: nil, fileLogLevel: nil)
        }
    }
}
