//
//  TangemLogger.swift
//  Multisig
//
//  Created by GPT-5 Codex.
//

import Foundation
#if MULTISIG_DEV_LOGS
import TangemSdk
#endif

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

#if MULTISIG_DEV_LOGS
struct TangemSdkLogAdapter: TangemSdkLogger {
    func log(_ message: String, level: Log.Level) {
        let formatted = "[TangemSDK]\(level.prefix) \(level.emoji) \(message)"
        switch level {
        case .error:
            LogService.shared.error(formatted)
        case .warning:
            LogService.shared.info(formatted)
        default:
            LogService.shared.debug(formatted)
        }
    }
}
#endif

internal extension Data {
    /// Hex string helper dedicated to Tangem debug traces.
    /// - Parameters:
    ///   - prefix: Adds `0x` when `true`.
    ///   - maxBytes: If provided, truncates the output to the first `maxBytes` bytes and appends an ellipsis.
    /// - Returns: Hex string representation suitable for debug logging.
    func tangemHexDescription(prefix: Bool = true, maxBytes: Int? = nil) -> String {
        var bytes = Array(self)
        var truncated = false

        if let maxBytes, count > maxBytes {
            bytes = Array(bytes.prefix(maxBytes))
            truncated = true
        }

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let base = (prefix ? "0x" : "") + hex
        return truncated ? base + "…" : base
    }
}

