import Foundation

/// Firewall Detector - Core detection logic
class FirewallDetector {
    private var urlList: [URLEntry]
    private let networkClient: NetworkClient
    private let cryptoHelper: CryptoHelper
    private var lastError: String?
    
    init() {
        self.urlList = Config.getBuiltinURLs()
        self.networkClient = NetworkClient()
        self.cryptoHelper = CryptoHelper()
        
        // Initialize crypto with public key
        _ = cryptoHelper.setPublicKey(pem: Config.getPublicKey())
    }
    
    /// Get final server domain (main entry point)
    func getFinalServer(customData: String?) async -> String? {
        Logger.shared.debug("getFinalServer() called with customData: \(customData ?? "nil")")
        Logger.shared.debug("URL list size: \(urlList.count)")
        
        // Loop infinitely until finding an available server
        while true {
            Logger.shared.debug("Starting URL iteration...")
            
            for entry in urlList {
                Logger.shared.debug("Checking URL: \(entry.url) (method: \(entry.method))")
                
                if let domain = await checkURLEntry(entry, customData: customData, recursionDepth: 0) {
                    Logger.shared.info("Found available server: \(domain)")
                    return domain
                }
                
                // Wait between URL checks
                try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
            }
            
            // All URLs failed, wait and retry
            lastError = "All URL detection failed, retrying..."
            Logger.shared.warning(lastError!)
            try? await Task.sleep(nanoseconds: UInt64(Config.retryInterval * 1_000_000_000))
        }
    }
    
    /// Set URL list
    func setURLList(_ urls: [URLEntry]) {
        self.urlList = urls
    }
    
    /// Add URL to list
    func addURL(method: String, url: String) {
        self.urlList.append(URLEntry(method: method, url: url))
    }
    
    /// Get last error
    func getLastError() -> String? {
        return lastError
    }
    
    // MARK: - Private Methods
    
    /// Check a single URL entry
    private func checkURLEntry(_ entry: URLEntry, customData: String?, recursionDepth: Int) async -> String? {
        lastError = nil
        
        // Check recursion depth limit
        guard recursionDepth <= Config.maxListRecursionDepth else {
            lastError = "Maximum list recursion depth exceeded: \(entry.url)"
            Logger.shared.error("Recursion depth limit reached (\(recursionDepth)) for URL: \(entry.url)")
            return nil
        }
        
        // Dispatch based on method
        switch entry.method.lowercased() {
        case "api":
            return await checkAPIURL(entry.url, customData: customData)
        case "file":
            return await checkFileURL(entry.url, customData: customData, recursionDepth: recursionDepth)
        default:
            lastError = "Unknown method: \(entry.method)"
            Logger.shared.error("Unknown method '\(entry.method)' for URL: \(entry.url)")
            return nil
        }
    }
    
    /// Check an API URL with retry mechanism
    private func checkAPIURL(_ url: String, customData: String?) async -> String? {
        Logger.shared.debug("CheckAPIURL() called for: \(url) with customData: \(customData ?? "nil")")
        
        guard !url.isEmpty else {
            lastError = "Empty URL provided"
            return nil
        }
        
        // Retry loop
        for attempt in 1...Config.maxRetries {
            Logger.shared.debug("Attempt \(attempt)/\(Config.maxRetries) for URL: \(url)")
            
            if let domain = await checkAPIURLOnce(url, customData: customData) {
                Logger.shared.info("Successfully verified URL: \(url) on attempt \(attempt)")
                return domain
            }
            
            // If this was the last attempt, give up
            if attempt == Config.maxRetries {
                Logger.shared.warning("All \(Config.maxRetries) attempts failed for URL: \(url). Last error: \(lastError ?? "unknown")")
                return nil
            }
            
            // Wait before retry
            Logger.shared.debug("Waiting \(Config.retryDelay)s before retry...")
            try? await Task.sleep(nanoseconds: UInt64(Config.retryDelay * 1_000_000_000))
        }
        
        return nil
    }
    
    /// Check an API URL once (no retry)
    private func checkAPIURLOnce(_ url: String, customData: String?) async -> String? {
        // 1. Generate random nonce
        guard let randomData = cryptoHelper.generateRandom(length: Config.nonceSize) else {
            lastError = "Failed to generate random data"
            return nil
        }
        let randomBase64 = randomData.base64EncodedString()
        Logger.shared.debug("Generated random data: \(randomData.count) bytes")
        
        // 2. Truncate custom data if too long
        var clientData = customData ?? ""
        if clientData.count > Config.maxClientDataSize {
            Logger.shared.warning("client_data truncated from \(clientData.count) to \(Config.maxClientDataSize) bytes")
            clientData = String(clientData.prefix(Config.maxClientDataSize))
        }
        
        // 3. Build JSON payload
        let payload: [String: String] = [
            "nonce": randomBase64,
            "client_data": clientData
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            lastError = "Failed to construct payload JSON"
            return nil
        }
        Logger.shared.debug("Payload JSON: \(payloadJSON)")
        
        // 4. Encrypt payload
        guard let payloadBytes = payloadJSON.data(using: .utf8),
              let encryptedData = cryptoHelper.encrypt(data: payloadBytes) else {
            lastError = "Failed to encrypt data"
            return nil
        }
        let encryptedBase64 = encryptedData.base64EncodedString()
        Logger.shared.debug("Encrypted data: \(encryptedData.count) bytes")
        
        // 5. Build request JSON
        let requestData: [String: String] = ["data": encryptedBase64]
        guard let requestJSON = try? JSONSerialization.data(withJSONObject: requestData),
              let requestBody = String(data: requestJSON, encoding: .utf8) else {
            lastError = "Failed to construct request JSON"
            return nil
        }
        
        // 6. POST request
        let response = await networkClient.post(url: url, jsonBody: requestBody)
        guard response.success else {
            lastError = "POST request failed: \(url) - \(response.error ?? "unknown")"
            return nil
        }
        
        // 7. Parse response JSON
        guard let responseData = response.body.data(using: .utf8),
              let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let returnedRandom = responseJSON["random"] as? String,
              let returnedDomain = responseJSON["domain"] as? String,
              let signature = responseJSON["signature"] as? String else {
            lastError = "Failed to parse response JSON or missing fields (random/domain/signature)"
            return nil
        }
        
        Logger.shared.debug("Returned random: \(returnedRandom)")
        Logger.shared.debug("Returned domain: \(returnedDomain)")
        
        // 8. Verify signature (sign response without signature field)
        // CRITICAL: Must use sorted keys to match server serialization
        var payloadForSigning = responseJSON
        payloadForSigning.removeValue(forKey: "signature")
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadForSigning, options: [.sortedKeys]) else {
            lastError = "Failed to serialize payload for verification"
            return nil
        }
        
        if let payloadString = String(data: payloadData, encoding: .utf8) {
            Logger.shared.debug("Payload for verification: \(payloadString)")
        }
        
        guard let signatureData = Data(base64Encoded: signature),
              cryptoHelper.verifySignature(data: payloadData, signature: signatureData) else {
            lastError = "Signature verification failed"
            return nil
        }
        
        // 10. Verify random matches
        guard returnedRandom == randomBase64 else {
            let expectedPrefix = String(randomBase64.prefix(10))
            let actualPrefix = String(returnedRandom.prefix(10))
            lastError = "Random mismatch: expected: \(expectedPrefix)..., actual: \(actualPrefix)..."
            return nil
        }
        
        // 11. Success!
        Logger.shared.debug("Verification successful! Using domain: \(returnedDomain)")
        return returnedDomain
    }
    
    /// Check a file URL (fetch sub-list and check each URL)
    private func checkFileURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        Logger.shared.debug("CheckFileURL() called for: \(url) (depth: \(recursionDepth))")
        
        guard !url.isEmpty else {
            lastError = "Empty file URL provided"
            return nil
        }
        
        // Fetch sub-list
        Logger.shared.debug("Fetching sub-list from: \(url)")
        let response = await networkClient.get(url: url)
        
        guard response.success else {
            lastError = "GET request failed: \(url) - \(response.error ?? "unknown")"
            return nil
        }
        
        // Try to parse as JSON first (new format with urls array)
        if let subEntries = parseURLEntriesJSON(content: response.body) {
            Logger.shared.debug("Fetched \(subEntries.count) URL entries from JSON sub-list, checking each one...")
            
            // Check each URL entry in sub-list
            for subEntry in subEntries {
                Logger.shared.debug("Checking sub-list entry: \(subEntry.url) (method: \(subEntry.method))")
                
                if let domain = await checkURLEntry(subEntry, customData: customData, recursionDepth: recursionDepth + 1) {
                    Logger.shared.info("Sub-list entry succeeded: \(subEntry.url) -> \(domain)")
                    return domain
                }
                
                Logger.shared.debug("Sub-list entry failed: \(subEntry.url), trying next...")
                try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
            }
        } else {
            // Fallback: parse as plain text URL list (legacy format)
            let subURLs = parseURLList(content: response.body)
            guard !subURLs.isEmpty else {
                lastError = "Sub-list empty or parse failed: \(url)"
                return nil
            }
            
            Logger.shared.debug("Fetched \(subURLs.count) URLs from text sub-list, checking each one...")
            
            // Check each URL in sub-list (assume API method)
            for subURL in subURLs {
                Logger.shared.debug("Checking sub-list URL: \(subURL)")
                let subEntry = URLEntry(method: "api", url: subURL)
                
                if let domain = await checkURLEntry(subEntry, customData: customData, recursionDepth: recursionDepth + 1) {
                    Logger.shared.info("Sub-list URL succeeded: \(subURL) -> \(domain)")
                    return domain
                }
                
                Logger.shared.debug("Sub-list URL failed: \(subURL), trying next...")
                try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
            }
        }
        
        // All URLs in sub-list failed
        Logger.shared.debug("All URLs in sub-list failed")
        lastError = "All URLs in sub-list failed: \(url)"
        return nil
    }
    
    /// Parse URL entries from content
    /// Supports:
    /// 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere)
    /// 2. Direct URLEntry[] JSON array format
    /// 3. Legacy {"urls": [...]} format
    private func parseURLEntriesJSON(content: String) -> [URLEntry]? {
        // Try to extract *PGFW*base64*PGFW* format first
        if let extracted = extractPGFWContent(from: content) {
            Logger.shared.debug("Found *PGFW* marker, extracted base64 length: \(extracted.count)")
            
            // Decode base64
            guard let decodedData = Data(base64Encoded: extracted),
                  let decodedString = String(data: decodedData, encoding: .utf8) else {
                Logger.shared.debug("Failed to decode base64 content")
                return nil
            }
            
            Logger.shared.debug("Decoded PGFW content: \(decodedString.prefix(200))...")
            
            // Parse as URLEntry[] JSON array
            if let entries = parseURLEntryArray(json: decodedString) {
                return entries
            }
        }
        
        // Fallback 1: Try to parse as direct URLEntry[] JSON array
        if let entries = parseURLEntryArray(json: content) {
            return entries
        }
        
        // Fallback 2: Try legacy {"urls": [...]} format
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlsArray = json["urls"] as? [[String: String]] else {
            return nil
        }
        
        var entries: [URLEntry] = []
        for urlDict in urlsArray {
            if let method = urlDict["method"], let url = urlDict["url"] {
                entries.append(URLEntry(method: method, url: url))
            }
        }
        
        return entries.isEmpty ? nil : entries
    }
    
    /// Extract content between *PGFW* markers
    private func extractPGFWContent(from text: String) -> String? {
        let startMarker = "*PGFW*"
        let endMarker = "*PGFW*"
        
        guard let startRange = text.range(of: startMarker),
              let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        
        let content = String(text[startRange.upperBound..<endRange.lowerBound])
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Parse URLEntry[] JSON array
    private func parseURLEntryArray(json: String) -> [URLEntry]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var entries: [URLEntry] = []
        for dict in array {
            if let method = dict["method"] as? String,
               let url = dict["url"] as? String {
                entries.append(URLEntry(method: method, url: url))
            }
        }
        
        return entries.isEmpty ? nil : entries
    }
    
    /// Parse URL list from text content
    private func parseURLList(content: String) -> [String] {
        var urls: [String] = []
        
        // Try to extract content between *GFW* markers
        let marker = "*GFW*"
        if let startRange = content.range(of: marker),
           let endRange = content.range(of: marker, range: startRange.upperBound..<content.endIndex) {
            let gfwContent = String(content[startRange.upperBound..<endRange.lowerBound])
            let trimmed = gfwContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !trimmed.isEmpty {
                // Parse URLs from marked content
                let lines = trimmed.components(separatedBy: .newlines)
                for line in lines {
                    let url = line.trimmingCharacters(in: .whitespaces)
                    if !url.isEmpty && !url.hasPrefix("#") {
                        urls.append(url)
                    }
                }
                return urls
            }
        }
        
        // If no markers found, parse entire content
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let url = line.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty && !url.hasPrefix("#") {
                urls.append(url)
            }
        }
        
        return urls
    }
}

