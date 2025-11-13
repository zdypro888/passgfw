import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Firewall Detector - Core detection logic
class FirewallDetector {
    private let networkClient: NetworkClient
    private let cryptoHelper: CryptoHelper
    private let urlManager: URLManager

    // 缓存最后成功的结果
    private var cachedResult: [String: Any]?
    private var lastError: String?

    init() {
        self.networkClient = NetworkClient(timeout: Config.requestTimeout)
        self.cryptoHelper = CryptoHelper()

        // Set public key
        let publicKey = Config.getPublicKey()
        if !cryptoHelper.setPublicKey(pem: publicKey) {
            Logger.shared.error("Failed to set public key")
        }

        // Initialize URL Manager
        let storage = KeychainStorage()
        self.urlManager = URLManager(storage: storage)

        Task {
            let success = await urlManager.initializeIfNeeded()
            if success {
                Logger.shared.info("URLManager initialized")
            } else {
                Logger.shared.warning("URLManager initialization failed")
            }
        }
    }

    /// Get domains by checking URL list
    /// - Parameters:
    ///   - retry: If true, force re-detection. If false, return cache if available.
    ///   - customData: Optional custom data to send with requests
    /// - Returns: Dictionary containing server response data, or nil if all attempts fail
    func getDomains(retry: Bool, customData: String?) async -> [String: Any]? {
        // If not retry and cache exists, return cache
        if !retry, let cached = cachedResult {
            Logger.shared.info("Returning cached result")
            return cached
        }

        // Perform detection
        Logger.shared.info("Starting detection (retry=\(retry))")

        // Infinite retry loop until success
        while true {
            let urls = await urlManager.getURLs()
            Logger.shared.debug("Checking \(urls.count) URLs")

            if let result = await checkURLsSequentially(entries: urls, customData: customData, recursionDepth: 0) {
                // Success - cache and return
                cachedResult = result
                Logger.shared.info("Detection succeeded")
                return result
            }

            // All failed, wait and retry
            lastError = "All URLs failed, retrying..."
            Logger.shared.warning(lastError!)
            try? await Task.sleep(nanoseconds: UInt64(Config.retryInterval * 1_000_000_000))
        }
    }

    /// Get last error
    func getLastError() -> String? {
        return lastError
    }

    // MARK: - Private Methods

    /// Check URLs sequentially
    private func checkURLsSequentially(entries: [URLEntry], customData: String?, recursionDepth: Int) async -> [String: Any]? {
        for entry in entries {
            Logger.shared.debug("Checking URL: \(entry.url) (method: \(entry.method), depth: \(recursionDepth))")

            if let result = await checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth) {
                Logger.shared.info("Found available server")
                return result
            }

            // Small delay between checks
            try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
        }
        return nil
    }

    /// Check single URL entry
    private func checkURLEntry(_ entry: URLEntry, customData: String?, recursionDepth: Int) async -> [String: Any]? {
        switch entry.method {
        case "api":
            return await checkAPIMethod(entry: entry, customData: customData)
        case "file":
            return await checkFileMethod(entry: entry, customData: customData, recursionDepth: recursionDepth)
        case "navigate":
            handleNavigateMethod(entry: entry)
            // Navigate 执行后算成功，返回表示已引导用户
            return ["navigated": true, "url": entry.url]
        case "remove":
            await handleRemoveMethod(entry: entry)
            // Remove 执行后继续下一个（返回nil）
            return nil
        default:
            Logger.shared.warning("Unknown method: \(entry.method)")
            return nil
        }
    }

    /// Check API method
    private func checkAPIMethod(entry: URLEntry, customData: String?) async -> [String: Any]? {
        // Generate random nonce
        guard let nonceData = cryptoHelper.generateRandom(length: Config.nonceSize) else {
            Logger.shared.error("Failed to generate random nonce")
            return nil
        }
        let randomBase64 = nonceData.base64EncodedString()

        // Determine OS name
        #if os(macOS)
        let osName = "macos"
        #else
        let osName = "ios"
        #endif

        // Get app bundle ID
        let appId = Bundle.main.bundleIdentifier ?? "unknown"

        // Prepare client data
        let clientData: [String: String] = ["domain": "example.com"]
        guard let clientDataBytes = try? JSONSerialization.data(withJSONObject: clientData),
              let clientDataStr = String(data: clientDataBytes, encoding: .utf8) else {
            Logger.shared.error("Failed to serialize client data")
            return nil
        }

        // Build request payload
        let payload: [String: String] = [
            "nonce": randomBase64,
            "os": osName,
            "app": appId,
            "data": customData ?? clientDataStr
        ]

        guard let payloadBytes = try? JSONSerialization.data(withJSONObject: payload) else {
            Logger.shared.error("Failed to serialize payload")
            return nil
        }

        // Encrypt payload
        guard let encryptedData = cryptoHelper.encrypt(data: payloadBytes) else {
            Logger.shared.error("Failed to encrypt payload")
            return nil
        }

        // Send request
        let response = await networkClient.post(url: entry.url, body: encryptedData)

        if !response.success {
            Logger.shared.warning("API request failed: \(response.error ?? "unknown error")")
            return nil
        }

        // Parse response
        guard let responseData = response.body.data(using: .utf8),
              let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            Logger.shared.error("Failed to parse response JSON")
            return nil
        }

        // Get nonce, data, signature (all base64 strings in JSON)
        guard let returnedNonceBase64 = responseJSON["nonce"] as? String,
              let dataBase64 = responseJSON["data"] as? String,
              let signatureBase64 = responseJSON["signature"] as? String else {
            Logger.shared.error("Invalid response format")
            return nil
        }

        // Verify nonce (decode and compare bytes)
        guard let returnedNonceData = Data(base64Encoded: returnedNonceBase64),
              returnedNonceData == nonceData else {
            Logger.shared.error("Nonce mismatch")
            return nil
        }

        // Decode data and signature
        guard let dataBytes = Data(base64Encoded: dataBase64),
              let signatureData = Data(base64Encoded: signatureBase64) else {
            Logger.shared.error("Invalid base64 encoding")
            return nil
        }

        // Rebuild response for verification (same structure as server)
        // IMPORTANT: Keep base64 strings, don't decode to []byte
        var responseForVerify: [String: Any] = [
            "nonce": returnedNonceBase64,
            "data": dataBase64
        ]

        // Add URLs if present
        if let urls = responseJSON["urls"] {
            responseForVerify["urls"] = urls
        }

        // Serialize with sorted keys to match Go's struct field order
        guard let verifyBytes = try? JSONSerialization.data(withJSONObject: responseForVerify, options: .sortedKeys) else {
            Logger.shared.error("Failed to serialize for verification")
            return nil
        }

        // Verify signature
        if !cryptoHelper.verifySignature(data: verifyBytes, signature: signatureData) {
            Logger.shared.error("Signature verification failed")
            return nil
        }

        Logger.shared.info("API check succeeded for \(entry.url)")

        // Parse data JSON
        guard let parsedData = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any] else {
            Logger.shared.error("Failed to parse data JSON")
            return nil
        }

        // Handle store flag
        if entry.store {
            let success = await urlManager.addURL(entry)
            Logger.shared.debug("Store URL \(entry.url): \(success)")
        }

        // Handle dynamic URLs from response
        if let urls = responseJSON["urls"] as? [[String: Any]] {
            await handleDynamicURLs(urls)
        }

        // Return parsed data
        return parsedData
    }

    /// Check file method
    private func checkFileMethod(entry: URLEntry, customData: String?, recursionDepth: Int) async -> [String: Any]? {
        // Check recursion depth
        if recursionDepth >= Config.maxListRecursionDepth {
            Logger.shared.warning("Max recursion depth reached")
            return nil
        }

        // Fetch file
        let response = await networkClient.get(url: entry.url)

        if !response.success {
            Logger.shared.warning("File request failed: \(response.error ?? "unknown error")")
            return nil
        }

        // Parse URL list
        guard let urls = parseURLList(response.body) else {
            Logger.shared.error("Failed to parse URL list")
            return nil
        }

        Logger.shared.info("File method: loaded \(urls.count) URLs from \(entry.url)")

        // Handle store flag
        if entry.store {
            let success = await urlManager.addURL(entry)
            Logger.shared.debug("Store file URL \(entry.url): \(success)")
        }

        // Check nested URLs
        return await checkURLsSequentially(entries: urls, customData: customData, recursionDepth: recursionDepth + 1)
    }

    /// Handle navigate method
    private func handleNavigateMethod(entry: URLEntry) {
        Logger.shared.info("Navigate method: opening \(entry.url)")
        if let url = URL(string: entry.url) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }
    }

    /// Handle remove method
    private func handleRemoveMethod(entry: URLEntry) async {
        Logger.shared.info("Remove method: removing \(entry.url)")
        _ = await urlManager.removeURL(url: entry.url)
        Logger.shared.debug("Remove URL \(entry.url)")
    }

    /// Handle dynamic URLs from API response
    private func handleDynamicURLs(_ urlsJSON: [[String: Any]]) async {
        for urlObj in urlsJSON {
            guard let method = urlObj["method"] as? String,
                  let url = urlObj["url"] as? String else {
                continue
            }

            let store = urlObj["store"] as? Bool ?? false
            let entry = URLEntry(method: method, url: url, store: store)

            switch method {
            case "remove":
                _ = await urlManager.removeURL(url: url)
                Logger.shared.debug("Dynamic remove: \(url)")
            case "api", "file":
                if store {
                    _ = await urlManager.addURL(entry)
                    Logger.shared.debug("Dynamic store: \(url)")
                }
            case "navigate":
                handleNavigateMethod(entry: entry)
            default:
                Logger.shared.warning("Unknown dynamic method: \(method)")
            }
        }
    }

    /// Parse URL list from text
    private func parseURLList(_ text: String) -> [URLEntry]? {
        // Try *PGFW* format first
        if let pgfwContent = extractPGFWContent(text) {
            if let urls = try? JSONDecoder().decode([URLEntry].self, from: Data(pgfwContent.utf8)) {
                return urls
            }
        }

        // Try direct JSON array
        if let data = text.data(using: .utf8),
           let urls = try? JSONDecoder().decode([URLEntry].self, from: data) {
            return urls
        }

        // Try legacy format {"urls": [...]}
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlsArray = json["urls"] as? [[String: Any]] {
            var entries: [URLEntry] = []
            for urlObj in urlsArray {
                guard let method = urlObj["method"] as? String,
                      let url = urlObj["url"] as? String else {
                    continue
                }
                let store = urlObj["store"] as? Bool ?? false
                entries.append(URLEntry(method: method, url: url, store: store))
            }
            return entries
        }

        // Fallback: plain text (one URL per line)
        let lines = text.components(separatedBy: .newlines)
        var entries: [URLEntry] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                entries.append(URLEntry(method: "api", url: trimmed, store: false))
            }
        }

        return entries.isEmpty ? nil : entries
    }

    /// Extract content from *PGFW*...* PGFW* markers
    private func extractPGFWContent(_ text: String) -> String? {
        let startMarker = "*PGFW*"
        let endMarker = "*PGFW*"

        guard let startRange = text.range(of: startMarker),
              let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }

        let base64String = String(text[startRange.upperBound..<endRange.lowerBound])
        guard let decodedData = Data(base64Encoded: base64String),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            return nil
        }

        return decodedString
    }
}
