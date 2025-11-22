//
//  BurnerLogger.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import Foundation
#if MULTISIG_DEV_LOGS
import OSLog
#endif

enum BurnerLogger {
    enum Level {
        case debug
        case info
        case warning
        case error
    }
    
    static func log(_ message: @autoclosure () -> String,
                    level: Level = .debug,
                    error: Error? = nil,
                    file: StaticString = #file,
                    line: UInt = #line,
                    function: StaticString = #function) {
#if MULTISIG_DEV_LOGS
        let formattedMessage = "[Burner] \(message())"
        switch level {
        case .debug:
            LogService.shared.debug(formattedMessage, error: error, file: file, line: line, function: function)
        case .info:
            LogService.shared.info(formattedMessage, error: error, file: file, line: line, function: function)
        case .warning:
            LogService.shared.info("⚠️ " + formattedMessage, error: error, file: file, line: line, function: function)
        case .error:
            LogService.shared.error(formattedMessage, error: error, file: file, line: line, function: function)
        }
#endif
    }
    
    static func debug(_ message: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: UInt = #line,
                      function: StaticString = #function) {
        log(message(), level: .debug, file: file, line: line, function: function)
    }
    
    static func info(_ message: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: UInt = #line,
                     function: StaticString = #function) {
        log(message(), level: .info, file: file, line: line, function: function)
    }
    
    static func warning(_ message: @autoclosure () -> String,
                        error: Error? = nil,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function) {
        log(message(), level: .warning, error: error, file: file, line: line, function: function)
    }
    
    static func error(_ message: @autoclosure () -> String,
                      error: Error? = nil,
                      file: StaticString = #file,
                      line: UInt = #line,
                      function: StaticString = #function) {
        log(message(), level: .error, error: error, file: file, line: line, function: function)
    }
}

extension Data {
    /// Hex string helper dedicated to Burner debug traces.
    func burnerHexDescription(prefix: Bool = true, maxBytes: Int? = nil) -> String {
        var bytes = Array(self)
        var truncated = false
        
        if let maxBytes, bytes.count > maxBytes {
            bytes = Array(bytes.prefix(maxBytes))
            truncated = true
        }
        
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let base = (prefix ? "0x" : "") + hex
        return truncated ? base + "…" : base
    }
}

