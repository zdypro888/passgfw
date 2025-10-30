import Foundation

/// PassGFW - Firewall Detection Library
/// 
/// Main entry point for the PassGFW library.
public class PassGFW {
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
    /// - Parameter urls: Array of URLs to check
    public func setURLList(_ urls: [String]) {
        detector.setURLList(urls)
    }
    
    /// Add a URL to the check list
    /// - Parameter url: URL to add
    public func addURL(_ url: String) {
        detector.addURL(url)
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

