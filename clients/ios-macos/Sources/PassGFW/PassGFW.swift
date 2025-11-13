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

    /// Get server domains by checking URL list
    /// - Parameters:
    ///   - retry: If true, force re-detection even if cache exists. If false, return cache if available.
    ///   - customData: Optional custom data to send with requests
    /// - Returns: Dictionary containing server response data, or nil if all attempts fail
    public func getDomains(retry: Bool = false, customData: String? = nil) async -> [String: Any]? {
        return await detector.getDomains(retry: retry, customData: customData)
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
