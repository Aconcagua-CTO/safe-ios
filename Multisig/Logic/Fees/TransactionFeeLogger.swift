//
//  TransactionFeeLogger.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

enum TransactionFeeLogger {
    enum Level {
        case debug
        case info
        case warning
        case error
    }

    private static func log(_ level: Level,
                            message: @autoclosure () -> String,
                            error: Error? = nil,
                            file: StaticString = #file,
                            line: UInt = #line,
                            function: StaticString = #function) {
        #if MULTISIG_DEV_LOGS
        let prefix: String
        switch level {
        case .debug:
            prefix = "🔍"
        case .info:
            prefix = "ℹ️"
        case .warning:
            prefix = "⚠️"
        case .error:
            prefix = "❌"
        }
        let formatted = "\(prefix) [FEE] \(message())"
        switch level {
        case .debug:
            LogService.shared.debug(formatted, error: error, file: file, line: line, function: function)
        case .info:
            LogService.shared.info(formatted, error: error, file: file, line: line, function: function)
        case .warning:
            LogService.shared.info(formatted, error: error, file: file, line: line, function: function)
        case .error:
            LogService.shared.error(formatted, error: error, file: file, line: line, function: function)
        }
        #endif
    }

    static func debug(_ message: @autoclosure () -> String,
                      error: Error? = nil,
                      file: StaticString = #file,
                      line: UInt = #line,
                      function: StaticString = #function) {
        log(.debug, message: message(), error: error, file: file, line: line, function: function)
    }

    static func info(_ message: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: UInt = #line,
                     function: StaticString = #function) {
        log(.info, message: message(), file: file, line: line, function: function)
    }

    static func warning(_ message: @autoclosure () -> String,
                        error: Error? = nil,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function) {
        log(.warning, message: message(), error: error, file: file, line: line, function: function)
    }

    static func error(_ message: @autoclosure () -> String,
                      error: Error? = nil,
                      file: StaticString = #file,
                      line: UInt = #line,
                      function: StaticString = #function) {
        log(.error, message: message(), error: error, file: file, line: line, function: function)
    }
}


