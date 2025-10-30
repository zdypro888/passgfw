import Foundation
import os.log

/// Log level
public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Logger for PassGFW
class Logger {
    static let shared = Logger()
    
    var isEnabled = true
    var minLevel: LogLevel = .debug
    
    private let osLog = OSLog(subsystem: "com.passgfw", category: "PassGFW")
    
    private init() {}
    
    func debug(_ message: String) {
        log(message, level: .debug, osLogType: .debug)
    }
    
    func info(_ message: String) {
        log(message, level: .info, osLogType: .info)
    }
    
    func warning(_ message: String) {
        log(message, level: .warning, osLogType: .default)
    }
    
    func error(_ message: String) {
        log(message, level: .error, osLogType: .error)
    }
    
    private func log(_ message: String, level: LogLevel, osLogType: OSLogType) {
        guard isEnabled && level >= minLevel else { return }
        
        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .warning: levelString = "WARNING"
        case .error: levelString = "ERROR"
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(levelString)] \(message)"
        
        os_log("%{public}@", log: osLog, type: osLogType, logMessage)
        
        #if DEBUG
        print(logMessage)
        #endif
    }
}

