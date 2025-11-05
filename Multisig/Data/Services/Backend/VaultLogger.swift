//
//  VaultLogger.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation

enum VaultLogger {
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
        let formattedMessage = "🔄 [VAULT_SYNC] \(message())"
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
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function) {
        log(message(), level: .warning, file: file, line: line, function: function)
    }

    static func error(_ message: @autoclosure () -> String,
                      error: Error? = nil,
                      file: StaticString = #file,
                      line: UInt = #line,
                      function: StaticString = #function) {
        log(message(), level: .error, error: error, file: file, line: line, function: function)
    }
    
    static func success(_ message: @autoclosure () -> String,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function) {
        #if MULTISIG_DEV_LOGS
        LogService.shared.info("✅ 🔄 [VAULT_SYNC] \(message())", file: file, line: line, function: function)
        #endif
    }
    
    static func network(_ message: @autoclosure () -> String,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function) {
        #if MULTISIG_DEV_LOGS
        LogService.shared.debug("📡 🔄 [VAULT_SYNC] \(message())", file: file, line: line, function: function)
        #endif
    }
    
    static func database(_ message: @autoclosure () -> String,
                         file: StaticString = #file,
                         line: UInt = #line,
                         function: StaticString = #function) {
        #if MULTISIG_DEV_LOGS
        LogService.shared.debug("💾 🔄 [VAULT_SYNC] \(message())", file: file, line: line, function: function)
        #endif
    }
}

