//
//  TangemLogger.swift
//  Multisig
//
//  Created by GPT-5 Codex.
//

import Foundation

enum TangemLogger {
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
        let formattedMessage = "[Tangem] \(message())"
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

