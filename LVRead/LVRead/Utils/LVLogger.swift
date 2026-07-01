import Foundation
import os.log

/// Centralized logging utility that replaces print statements.
/// Uses OSLog in production for better performance and filtering.
final class LVLogger {
    
    enum Level: Int, Comparable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        
        var osLogType: OSLogType {
            switch self {
            case .verbose, .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
        
        static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    enum Category: String {
        case network = "Network"
        case parser = "Parser"
        case database = "Database"
        case ui = "UI"
        case general = "General"
    }
    
    #if DEBUG
    static var minimumLevel: Level = .debug
    #else
    static var minimumLevel: Level = .info
    #endif
    
    static func log(
        _ message: String,
        level: Level = .info,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(category.rawValue)] \(message) (\(fileName):\(line))"
        
        #if DEBUG
        let prefix: String
        switch level {
        case .verbose: prefix = "🔍"
        case .debug: prefix = "🔧"
        case .info: prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error: prefix = "❌"
        }
        print("\(prefix) \(logMessage)")
        #else
        let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.lvread.app", category: category.rawValue)
        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)
        #endif
    }
    
    static func verbose(_ message: String, category: Category = .general) {
        log(message, level: .verbose, category: category)
    }
    
    static func debug(_ message: String, category: Category = .general) {
        log(message, level: .debug, category: category)
    }
    
    static func info(_ message: String, category: Category = .general) {
        log(message, level: .info, category: category)
    }
    
    static func warning(_ message: String, category: Category = .general) {
        log(message, level: .warning, category: category)
    }
    
    static func error(_ message: String, category: Category = .general) {
        log(message, level: .error, category: category)
    }
}
