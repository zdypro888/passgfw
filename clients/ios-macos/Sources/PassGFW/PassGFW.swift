import Foundation

/// PassGFW - Firewall Detection Library
/// 
/// Main entry point for the PassGFW library.
public class PassGFWClient {
    private let detector: FirewallDetector
    
    /// Initialize PassGFW with default configuration
    public init() {
        self.detector = FirewallDetector()
    }
    
    /// Get the final available server domain
    /// - Parameter customData: Optional custom data to send with requests
    /// - Returns: The final server domain, or nil if all attempts fail
    public func getFinalServer(customData: String? = nil) async -> String? {
        return await detector.getFinalServer(customData: customData)
    }
    
    /// Set the URL list to check
    /// - Parameter entries: Array of URL entries to check
    ///
    /// 注意：此方法已废弃，建议使用 addURL 方法逐个添加
    /// URLs 将被持久化到存储中
    @available(*, deprecated, message: "Use addURL instead for better control")
    public func setURLList(_ entries: [URLEntry]) {
        // 批量添加 URL 到存储（异步操作）
        for entry in entries {
            detector.addURL(method: entry.method, url: entry.url)
        }
    }
    
    /// Add a URL entry to the check list
    /// - Parameters:
    ///   - method: Method type ("api" or "file")
    ///   - url: URL to add
    public func addURL(method: String, url: String) {
        detector.addURL(method: method, url: url)
    }
    
    /// Get the last error message
    /// - Returns: Last error message, or nil if no error
    public func getLastError() -> String? {
        return detector.getLastError()
    }
    
    /// Enable or disable logging
    /// - Parameter enabled: Whether to enable logging
    public func setLoggingEnabled(_ enabled: Bool) {
        Logger.shared.isEnabled = enabled
    }
    
    /// Set the minimum log level
    /// - Parameter level: Minimum log level to display
    public func setLogLevel(_ level: LogLevel) {
        Logger.shared.minLevel = level
    }
}
