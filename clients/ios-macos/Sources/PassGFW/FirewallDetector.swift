import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Firewall Detector - Core detection logic
class FirewallDetector {
    private var urlList: [URLEntry]
    private let networkClient: NetworkClient
    private let cryptoHelper: CryptoHelper
    private var lastError: String?

    // 记录已打开的 navigate URLs，避免重复打开
    private var openedNavigateURLs: Set<String> = []

    init() {
        // Load builtin URLs + stored URLs
        var allURLs = Config.getBuiltinURLs()
        let storedURLs = URLStorageManager.shared.loadStoredURLs()
        
        if !storedURLs.isEmpty {
            Logger.shared.info("Loaded \(storedURLs.count) stored URLs from local file")
            allURLs.append(contentsOf: storedURLs)
        }
        
        self.urlList = allURLs
        self.networkClient = NetworkClient()
        self.cryptoHelper = CryptoHelper()
        
        // Initialize crypto with public key
        _ = cryptoHelper.setPublicKey(pem: Config.getPublicKey())
        
        Logger.shared.debug("Total URLs loaded: \(urlList.count) (builtin: \(Config.getBuiltinURLs().count), stored: \(storedURLs.count))")
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

        // Handle "remove" method - 从存储中删除 URL
        if entry.method.lowercased() == "remove" {
            Logger.shared.info("删除本地存储中的 URL: \(entry.url)")
            if URLStorageManager.shared.removeURL(entry.url) {
                Logger.shared.info("成功删除 URL: \(entry.url)")
            } else {
                Logger.shared.warning("删除失败（URL 可能不存在）: \(entry.url)")
            }
            // 不检查此 URL，直接跳过
            return nil
        }

        // Handle "navigate" method - 打开浏览器
        if entry.method.lowercased() == "navigate" {
            // 检查是否已经打开过，避免重复打开
            if openedNavigateURLs.contains(entry.url) {
                Logger.shared.debug("Navigate URL 已打开过，跳过: \(entry.url)")
                return nil
            }

            Logger.shared.info("打开浏览器导航到: \(entry.url)")

            // 尝试打开浏览器
            if let url = URL(string: entry.url) {
                #if canImport(UIKit)
                // iOS
                await UIApplication.shared.open(url)
                Logger.shared.info("已在 iOS 默认浏览器中打开: \(entry.url)")
                #elseif canImport(AppKit)
                // macOS
                NSWorkspace.shared.open(url)
                Logger.shared.info("已在 macOS 默认浏览器中打开: \(entry.url)")
                #endif

                // 记录已打开
                openedNavigateURLs.insert(entry.url)
            } else {
                Logger.shared.error("Navigate URL 格式无效: \(entry.url)")
            }

            // 打开浏览器后继续检测下一个 URL
            return nil
        }

        // Dispatch based on method
        var result: String? = nil

        switch entry.method.lowercased() {
        case "api":
            result = await checkAPIURL(entry.url, customData: customData, recursionDepth: recursionDepth)
        case "file":
            result = await checkFileURL(entry.url, customData: customData, recursionDepth: recursionDepth)
        default:
            lastError = "Unknown method: \(entry.method)"
            Logger.shared.error("未知的 method '\(entry.method)' for URL: \(entry.url)")
            return nil
        }

        // 如果检查成功且 store=true，则异步持久化存储此 URL（不阻塞返回）
        if result != nil, entry.store == true {
            let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)

            // 后台异步存储，不阻塞返回
            Task.detached(priority: .background) {
                Logger.shared.info("后台存储检测成功的 URL: \(entry.url) (method: \(entry.method))")
                if URLStorageManager.shared.addURL(storedEntry) {
                    Logger.shared.info("成功存储 URL: \(entry.url)")
                } else {
                    Logger.shared.error("存储 URL 失败: \(entry.url)")
                }
            }
        }

        return result
    }
    
    /// Check an API URL with retry mechanism
    private func checkAPIURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        Logger.shared.debug("CheckAPIURL() called for: \(url) with customData: \(customData ?? "nil")")

        guard !url.isEmpty else {
            lastError = "Empty URL provided"
            return nil
        }

        // Retry loop
        for attempt in 1...Config.maxRetries {
            Logger.shared.debug("Attempt \(attempt)/\(Config.maxRetries) for URL: \(url)")

            if let domain = await checkAPIURLOnce(url, customData: customData, recursionDepth: recursionDepth) {
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
    private func checkAPIURLOnce(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
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
              let signature = responseJSON["signature"] as? String else {
            lastError = "Failed to parse response JSON or missing required fields (random/signature)"
            return nil
        }

        // domain 和 urls 都是可选的
        let returnedDomain = responseJSON["domain"] as? String

        Logger.shared.debug("Returned random: \(returnedRandom)")
        if let domain = returnedDomain {
            Logger.shared.debug("Returned domain: \(domain)")
        }

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

        // 9. Verify random matches
        guard returnedRandom == randomBase64 else {
            let expectedPrefix = String(randomBase64.prefix(10))
            let actualPrefix = String(returnedRandom.prefix(10))
            lastError = "Random mismatch: expected: \(expectedPrefix)..., actual: \(actualPrefix)..."
            return nil
        }

        // 10. 处理服务器返回的 urls 数组（如果有）
        if let urlsData = responseJSON["urls"] as? [[String: Any]] {
            Logger.shared.debug("Server returned \(urlsData.count) URLs in response")

            var urlEntries: [URLEntry] = []
            for urlDict in urlsData {
                if let method = urlDict["method"] as? String,
                   let url = urlDict["url"] as? String {
                    let store = urlDict["store"] as? Bool ?? false
                    urlEntries.append(URLEntry(method: method, url: url, store: store))
                }
            }

            // 策略：如果有 domain，说明服务器可信，异步存储 store=true 的 URL（不阻塞返回）
            if returnedDomain != nil {
                for entry in urlEntries where entry.store == true {
                    let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)
                    // 后台异步存储，不阻塞返回
                    Task.detached(priority: .background) {
                        Logger.shared.info("后台存储服务器推荐的 URL: \(entry.url) (method: \(entry.method))")
                        if URLStorageManager.shared.addURL(storedEntry) {
                            Logger.shared.info("成功存储 URL: \(entry.url)")
                        } else {
                            Logger.shared.error("存储 URL 失败: \(entry.url)")
                        }
                    }
                }
            } else {
                // 没有 domain，循环检测 urls，只存储检测成功的
                Logger.shared.debug("No domain in response, checking URLs from server...")

                for entry in urlEntries {
                    Logger.shared.debug("Checking server-provided URL: \(entry.url) (method: \(entry.method))")

                    if let domain = await checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth + 1) {
                        Logger.shared.info("Server-provided URL succeeded: \(entry.url) -> \(domain)")

                        // 检测成功，异步存储（不阻塞返回）
                        if entry.store == true {
                            let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)
                            Task.detached(priority: .background) {
                                Logger.shared.info("后台存储检测成功的 URL: \(entry.url)")
                                _ = URLStorageManager.shared.addURL(storedEntry)
                            }
                        }

                        return domain
                    }

                    Logger.shared.debug("Server-provided URL failed: \(entry.url), trying next...")
                    try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
                }

                lastError = "All server-provided URLs failed"
                return nil
            }
        }

        // 11. 如果有 domain，返回它
        if let domain = returnedDomain {
            Logger.shared.debug("Verification successful! Using domain: \(domain)")
            return domain
        }

        // 既没有 domain 也没有 urls
        lastError = "Response has neither domain nor urls"
        return nil
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
    
    /// 智能解析 URL entries（支持多种格式）
    /// Supports:
    /// 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere including HTML)
    /// 2. Direct URLEntry[] JSON array format
    /// 3. Legacy {"urls": [...]} format
    /// 4. HTML with <pre>, <code>, or <script type="application/json"> tags
    private func parseURLEntriesJSON(content: String) -> [URLEntry]? {
        Logger.shared.debug("开始智能解析内容（长度: \(content.count)）")

        // 策略1: 尝试提取 *PGFW*base64*PGFW* 标记（优先级最高，可嵌入任何格式）
        if let extracted = extractPGFWContent(from: content) {
            Logger.shared.info("✓ 检测到 *PGFW* 标记格式")

            guard let decodedData = Data(base64Encoded: extracted),
                  let decodedString = String(data: decodedData, encoding: .utf8) else {
                Logger.shared.warning("× Base64 解码失败")
                return nil
            }

            Logger.shared.debug("解码内容: \(decodedString.prefix(200))...")

            if let entries = parseURLEntryArray(json: decodedString) {
                Logger.shared.info("✓ 成功解析 *PGFW* 格式，获得 \(entries.count) 个 URL")
                return entries
            }
        }

        // 策略2: 检测是否为 HTML，提取特定标签内容
        if content.contains("<html") || content.contains("<!DOCTYPE") {
            Logger.shared.info("✓ 检测到 HTML 格式，尝试提取内容...")

            // 尝试提取 <pre> 标签内容
            if let preContent = extractHTMLTag(from: content, tag: "pre") {
                Logger.shared.debug("从 <pre> 标签提取到内容")
                if let entries = parseURLEntryArray(json: preContent) {
                    Logger.shared.info("✓ 成功从 HTML <pre> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            // 尝试提取 <code> 标签内容
            if let codeContent = extractHTMLTag(from: content, tag: "code") {
                Logger.shared.debug("从 <code> 标签提取到内容")
                if let entries = parseURLEntryArray(json: codeContent) {
                    Logger.shared.info("✓ 成功从 HTML <code> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            // 尝试提取 <script type="application/json"> 内容
            if let scriptContent = extractJSONScript(from: content) {
                Logger.shared.debug("从 <script> 标签提取到 JSON")
                if let entries = parseURLEntryArray(json: scriptContent) {
                    Logger.shared.info("✓ 成功从 HTML <script> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            Logger.shared.warning("× HTML 中未找到有效的 URL 数据")
        }

        // 策略3: 尝试直接解析为 URLEntry[] JSON 数组
        if let entries = parseURLEntryArray(json: content) {
            Logger.shared.info("✓ 成功解析为直接 JSON 数组，获得 \(entries.count) 个 URL")
            return entries
        }

        // 策略4: 尝试 legacy {"urls": [...]} 格式
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlsArray = json["urls"] as? [[String: String]] {

            var entries: [URLEntry] = []
            for urlDict in urlsArray {
                if let method = urlDict["method"], let url = urlDict["url"] {
                    let store = urlDict["store"] == "true" || urlDict["store"] == "1"
                    entries.append(URLEntry(method: method, url: url, store: store))
                }
            }

            if !entries.isEmpty {
                Logger.shared.info("✓ 成功解析为 Legacy 格式，获得 \(entries.count) 个 URL")
                return entries
            }
        }

        Logger.shared.warning("× 所有 JSON 解析策略均失败")
        return nil
    }

    /// 从 HTML 中提取指定标签的内容
    private func extractHTMLTag(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let content = String(html[contentRange])
        // 解码 HTML entities
        return content
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 HTML 中提取 <script type="application/json"> 的内容
    private func extractJSONScript(from html: String) -> String? {
        let pattern = "<script[^>]*type=[\"']application/json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
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

