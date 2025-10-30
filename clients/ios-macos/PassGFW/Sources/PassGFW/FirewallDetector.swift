import Foundation

/// Firewall Detector - Core detection logic
class FirewallDetector {
    private var urlList: [String]
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
            
            for url in urlList {
                Logger.shared.debug("Checking URL: \(url)")
                
                if let domain = await checkURL(url, customData: customData, recursionDepth: 0) {
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
    func setURLList(_ urls: [String]) {
        self.urlList = urls
    }
    
    /// Add URL to list
    func addURL(_ url: String) {
        self.urlList.append(url)
    }
    
    /// Get last error
    func getLastError() -> String? {
        return lastError
    }
    
    // MARK: - Private Methods
    
    /// Check a single URL (with recursion support for list#)
    private func checkURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        lastError = nil
        
        // Check recursion depth limit
        guard recursionDepth <= Config.maxListRecursionDepth else {
            lastError = "Maximum list recursion depth exceeded: \(url)"
            Logger.shared.error("Recursion depth limit reached (\(recursionDepth)) for URL: \(url)")
            return nil
        }
        
        // Check if it's a list URL (ending with #)
        if url.hasSuffix("#") {
            return await checkListURL(url, customData: customData, recursionDepth: recursionDepth)
        } else {
            return await checkNormalURL(url, customData: customData)
        }
    }
    
    /// Check a normal URL with retry mechanism
    private func checkNormalURL(_ url: String, customData: String?) async -> String? {
        Logger.shared.debug("CheckNormalURL() called for: \(url) with customData: \(customData ?? "nil")")
        
        guard !url.isEmpty else {
            lastError = "Empty URL provided"
            return nil
        }
        
        // Retry loop
        for attempt in 1...Config.maxRetries {
            Logger.shared.debug("Attempt \(attempt)/\(Config.maxRetries) for URL: \(url)")
            
            if let domain = await checkNormalURLOnce(url, customData: customData) {
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
    
    /// Check a normal URL once (no retry)
    private func checkNormalURLOnce(_ url: String, customData: String?) async -> String? {
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
              let serverResponseJSON = responseJSON["data"] as? String,
              let signature = responseJSON["signature"] as? String else {
            lastError = "Failed to parse response JSON or missing fields"
            return nil
        }
        
        Logger.shared.debug("Server response JSON: \(serverResponseJSON)")
        
        // 8. Verify signature
        guard let serverResponseData = serverResponseJSON.data(using: .utf8),
              let signatureData = Data(base64Encoded: signature),
              cryptoHelper.verifySignature(data: serverResponseData, signature: signatureData) else {
            lastError = "Signature verification failed"
            return nil
        }
        
        // 9. Parse server payload
        guard let serverPayloadData = serverResponseJSON.data(using: .utf8),
              let serverPayload = try? JSONSerialization.jsonObject(with: serverPayloadData) as? [String: String],
              let returnedNonce = serverPayload["nonce"],
              let returnedDomain = serverPayload["server_domain"] else {
            lastError = "Failed to parse server payload or missing fields"
            return nil
        }
        
        Logger.shared.debug("Returned nonce: \(returnedNonce)")
        Logger.shared.debug("Returned domain: \(returnedDomain)")
        
        // 10. Verify nonce matches
        guard returnedNonce == randomBase64 else {
            let expectedPrefix = String(randomBase64.prefix(10))
            let actualPrefix = String(returnedNonce.prefix(10))
            lastError = "Nonce mismatch: expected: \(expectedPrefix)..., actual: \(actualPrefix)..."
            return nil
        }
        
        // 11. Success!
        Logger.shared.debug("Verification successful! Using domain: \(returnedDomain)")
        return returnedDomain
    }
    
    /// Check a list URL (fetch sub-list and check each URL)
    private func checkListURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        Logger.shared.debug("CheckListURL() called for: \(url) (depth: \(recursionDepth))")
        
        guard url.count >= 2 else {
            lastError = "Invalid list URL: too short"
            return nil
        }
        
        // Remove trailing #
        let actualURL = String(url.dropLast())
        guard !actualURL.isEmpty else {
            lastError = "Empty URL after removing #"
            return nil
        }
        
        // Fetch sub-list
        Logger.shared.debug("Fetching sub-list from: \(actualURL)")
        let response = await networkClient.get(url: actualURL)
        
        guard response.success else {
            lastError = "GET request failed: \(actualURL) - \(response.error ?? "unknown")"
            return nil
        }
        
        // Parse URL list
        let subURLs = parseURLList(content: response.body)
        guard !subURLs.isEmpty else {
            lastError = "Sub-list empty or parse failed: \(actualURL)"
            return nil
        }
        
        Logger.shared.debug("Fetched \(subURLs.count) URLs from sub-list, checking each one...")
        
        // Check each URL in sub-list
        for subURL in subURLs {
            Logger.shared.debug("Checking sub-list URL: \(subURL)")
            
            if let domain = await checkURL(subURL, customData: customData, recursionDepth: recursionDepth + 1) {
                Logger.shared.info("Sub-list URL succeeded: \(subURL) -> \(domain)")
                return domain
            }
            
            Logger.shared.debug("Sub-list URL failed: \(subURL), trying next...")
            try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
        }
        
        // All URLs in sub-list failed
        Logger.shared.debug("All URLs in sub-list failed")
        lastError = "All URLs in sub-list failed: \(actualURL)"
        return nil
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

