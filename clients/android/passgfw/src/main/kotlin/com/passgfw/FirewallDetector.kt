package com.passgfw

import android.util.Base64
import com.google.gson.Gson
import kotlinx.coroutines.delay

/**
 * Firewall Detector - Core detection logic
 */
class FirewallDetector {
    private var urlList: MutableList<URLEntry>
    private val networkClient = NetworkClient()
    private val cryptoHelper = CryptoHelper()
    private var lastError: String? = null
    
    init {
        // Load builtin URLs + stored URLs
        val allURLs = Config.getBuiltinURLs().toMutableList()
        val storedURLs = try {
            URLStorageManager.getInstance().loadStoredURLs()
        } catch (e: Exception) {
            Logger.warning("URLStorageManager not initialized yet: ${e.message}")
            emptyList()
        }
        
        if (storedURLs.isNotEmpty()) {
            Logger.info("Loaded ${storedURLs.size} stored URLs from local file")
            allURLs.addAll(storedURLs)
        }
        
        urlList = allURLs
        
        // Initialize crypto with public key
        cryptoHelper.setPublicKey(Config.getPublicKey())
        
        Logger.debug("Total URLs loaded: ${urlList.size} (builtin: ${Config.getBuiltinURLs().size}, stored: ${storedURLs.size})")
    }
    
    /**
     * Get final server domain (main entry point)
     */
    suspend fun getFinalServer(customData: String?): String? {
        Logger.debug("getFinalServer() called with customData: $customData")
        Logger.debug("URL list size: ${urlList.size}")
        
        // Loop infinitely until finding an available server
        while (true) {
            Logger.debug("Starting URL iteration...")
            
            for (entry in urlList) {
                Logger.debug("Checking URL: ${entry.url} (method: ${entry.method})")
                
                checkURLEntry(entry, customData, 0)?.let { domain ->
                    Logger.info("Found available server: $domain")
                    return domain
                }
                
                // Wait between URL checks
                delay(Config.URL_INTERVAL)
            }
            
            // All URLs failed, wait and retry
            lastError = "All URL detection failed, retrying..."
            Logger.warning(lastError!!)
            delay(Config.RETRY_INTERVAL)
        }
    }
    
    /**
     * Set URL list
     */
    fun setURLList(urls: List<URLEntry>) {
        this.urlList = urls.toMutableList()
    }
    
    /**
     * Add URL to list
     */
    fun addURL(method: String, url: String) {
        this.urlList.add(URLEntry(method, url))
    }
    
    /**
     * Get last error
     */
    fun getLastError(): String? = lastError
    
    // MARK: - Private Methods
    
    /**
     * Check a single URL entry
     */
    private suspend fun checkURLEntry(entry: URLEntry, customData: String?, recursionDepth: Int): String? {
        lastError = null

        // Check recursion depth limit
        if (recursionDepth > Config.MAX_LIST_RECURSION_DEPTH) {
            lastError = "Maximum list recursion depth exceeded: ${entry.url}"
            Logger.error("Recursion depth limit reached ($recursionDepth) for URL: ${entry.url}")
            return null
        }

        // Handle "remove" method - 从存储中删除 URL
        if (entry.method.lowercase() == "remove") {
            Logger.info("删除本地存储中的 URL: ${entry.url}")
            try {
                val manager = URLStorageManager.getInstance()
                if (manager.removeURL(entry.url)) {
                    Logger.info("成功删除 URL: ${entry.url}")
                } else {
                    Logger.warning("删除失败（URL 可能不存在）: ${entry.url}")
                }
            } catch (e: Exception) {
                Logger.error("URLStorageManager not available: ${e.message}")
            }
            // 不检查此 URL，直接跳过
            return null
        }

        // Dispatch based on method
        val result = when (entry.method.lowercase()) {
            "api" -> checkAPIURL(entry.url, customData, recursionDepth)
            "file" -> checkFileURL(entry.url, customData, recursionDepth)
            else -> {
                lastError = "Unknown method: ${entry.method}"
                Logger.error("未知的 method '${entry.method}' for URL: ${entry.url}")
                null
            }
        }

        // 如果检查成功且 store=true，则异步持久化存储此 URL（不阻塞返回）
        if (result != null && entry.store) {
            val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)

            // 后台异步存储，不阻塞返回
            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                Logger.info("后台存储检测成功的 URL: ${entry.url} (method: ${entry.method})")
                try {
                    val manager = URLStorageManager.getInstance()
                    if (manager.addURL(storedEntry)) {
                        Logger.info("成功存储 URL: ${entry.url}")
                    } else {
                        Logger.error("存储 URL 失败: ${entry.url}")
                    }
                } catch (e: Exception) {
                    Logger.error("URLStorageManager not available: ${e.message}")
                }
            }
        }

        return result
    }
    
    /**
     * Check an API URL with retry mechanism
     */
    private suspend fun checkAPIURL(url: String, customData: String?, recursionDepth: Int): String? {
        Logger.debug("CheckAPIURL() called for: $url with customData: $customData")

        if (url.isEmpty()) {
            lastError = "Empty URL provided"
            return null
        }

        // Retry loop
        for (attempt in 1..Config.MAX_RETRIES) {
            Logger.debug("Attempt $attempt/${Config.MAX_RETRIES} for URL: $url")

            checkNormalURLOnce(url, customData, recursionDepth)?.let { domain ->
                Logger.info("Successfully verified URL: $url on attempt $attempt")
                return domain
            }

            // If this was the last attempt, give up
            if (attempt == Config.MAX_RETRIES) {
                Logger.warning("All ${Config.MAX_RETRIES} attempts failed for URL: $url. Last error: ${lastError ?: "unknown"}")
                return null
            }

            // Wait before retry
            Logger.debug("Waiting ${Config.RETRY_DELAY}ms before retry...")
            delay(Config.RETRY_DELAY)
        }

        return null
    }
    
    /**
     * Check a normal URL once (no retry)
     */
    private suspend fun checkNormalURLOnce(url: String, customData: String?, recursionDepth: Int): String? {
        val gson = Gson()

        // 1. Generate random nonce
        val randomData = cryptoHelper.generateRandom(Config.NONCE_SIZE)
        val randomBase64 = Base64.encodeToString(randomData, Base64.NO_WRAP)
        Logger.debug("Generated random data: ${randomData.size} bytes")

        // 2. Truncate custom data if too long
        var clientData = customData ?: ""
        if (clientData.length > Config.MAX_CLIENT_DATA_SIZE) {
            Logger.warning("client_data truncated from ${clientData.length} to ${Config.MAX_CLIENT_DATA_SIZE} bytes")
            clientData = clientData.substring(0, Config.MAX_CLIENT_DATA_SIZE)
        }

        // 3. Build JSON payload
        val payload = mapOf(
            "nonce" to randomBase64,
            "client_data" to clientData
        )
        val payloadJSON = gson.toJson(payload)
        Logger.debug("Payload JSON: $payloadJSON")

        // 4. Encrypt payload
        val encryptedData = cryptoHelper.encrypt(payloadJSON.toByteArray(Charsets.UTF_8))
        if (encryptedData == null) {
            lastError = "Failed to encrypt data"
            return null
        }
        val encryptedBase64 = Base64.encodeToString(encryptedData, Base64.NO_WRAP)
        Logger.debug("Encrypted data: ${encryptedData.size} bytes")

        // 5. Build request JSON
        val requestData = mapOf("data" to encryptedBase64)
        val requestBody = gson.toJson(requestData)

        // 6. POST request
        val response = networkClient.post(url, requestBody)
        if (!response.success) {
            lastError = "POST request failed: $url - ${response.error}"
            return null
        }

        // 7. Parse response JSON
        val responseJSON = try {
            gson.fromJson(response.body, Map::class.java) as? Map<*, *>
        } catch (e: Exception) {
            lastError = "Failed to parse response JSON: ${e.message}"
            return null
        }

        val returnedRandom = responseJSON?.get("random") as? String
        val signature = responseJSON?.get("signature") as? String

        if (returnedRandom == null || signature == null) {
            lastError = "Response JSON missing required fields (random/signature)"
            return null
        }

        // domain 和 urls 都是可选的
        val returnedDomain = responseJSON?.get("domain") as? String

        Logger.debug("Returned random: $returnedRandom")
        if (returnedDomain != null) {
            Logger.debug("Returned domain: $returnedDomain")
        }

        // 8. Verify signature (sign response without signature field)
        // CRITICAL: Must use sorted keys to match server serialization
        val payloadForSigning = sortedMapOf<String, Any>()
        responseJSON.forEach { (key, value) ->
            if (key != "signature") {
                payloadForSigning[key] = value
            }
        }

        val payloadJSON2 = gson.toJson(payloadForSigning)
        Logger.debug("Payload for verification: $payloadJSON2")

        val payloadData = payloadJSON2.toByteArray(Charsets.UTF_8)
        val signatureData = Base64.decode(signature, Base64.DEFAULT)

        if (!cryptoHelper.verifySignature(payloadData, signatureData)) {
            lastError = "Signature verification failed"
            return null
        }

        // 9. Verify random matches
        if (returnedRandom != randomBase64) {
            val expectedPrefix = randomBase64.take(10)
            val actualPrefix = returnedRandom.take(10)
            lastError = "Random mismatch: expected: $expectedPrefix..., actual: $actualPrefix..."
            return null
        }

        // 10. 处理服务器返回的 urls 数组（如果有）
        val urlsData = responseJSON?.get("urls") as? List<*>
        if (urlsData != null) {
            Logger.debug("Server returned ${urlsData.size} URLs in response")

            val urlEntries = mutableListOf<URLEntry>()
            for (urlDict in urlsData) {
                val dict = urlDict as? Map<*, *> ?: continue
                val method = dict["method"] as? String ?: continue
                val urlStr = dict["url"] as? String ?: continue
                val store = dict["store"] as? Boolean ?: false
                urlEntries.add(URLEntry(method = method, url = urlStr, store = store))
            }

            // 策略：如果有 domain，说明服务器可信，异步存储 store=true 的 URL（不阻塞返回）
            if (returnedDomain != null) {
                for (entry in urlEntries) {
                    if (entry.store) {
                        val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)
                        // 后台异步存储，不阻塞返回
                        kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                            Logger.info("后台存储服务器推荐的 URL: ${entry.url} (method: ${entry.method})")
                            try {
                                val manager = URLStorageManager.getInstance()
                                if (manager.addURL(storedEntry)) {
                                    Logger.info("成功存储 URL: ${entry.url}")
                                } else {
                                    Logger.error("存储 URL 失败: ${entry.url}")
                                }
                            } catch (e: Exception) {
                                Logger.error("URLStorageManager not available: ${e.message}")
                            }
                        }
                    }
                }
            } else {
                // 没有 domain，循环检测 urls，只存储检测成功的
                Logger.debug("No domain in response, checking URLs from server...")

                for (entry in urlEntries) {
                    Logger.debug("Checking server-provided URL: ${entry.url} (method: ${entry.method})")

                    checkURLEntry(entry, customData, recursionDepth + 1)?.let { domain ->
                        Logger.info("Server-provided URL succeeded: ${entry.url} -> $domain")

                        // 检测成功，异步存储（不阻塞返回）
                        if (entry.store) {
                            val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)
                            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                                Logger.info("后台存储检测成功的 URL: ${entry.url}")
                                try {
                                    URLStorageManager.getInstance().addURL(storedEntry)
                                } catch (e: Exception) {
                                    Logger.error("Failed to store URL: ${e.message}")
                                }
                            }
                        }

                        return domain
                    }

                    Logger.debug("Server-provided URL failed: ${entry.url}, trying next...")
                    delay(Config.URL_INTERVAL)
                }

                lastError = "All server-provided URLs failed"
                return null
            }
        }

        // 11. 如果有 domain，返回它
        if (returnedDomain != null) {
            Logger.debug("Verification successful! Using domain: $returnedDomain")
            return returnedDomain
        }

        // 既没有 domain 也没有 urls
        lastError = "Response has neither domain nor urls"
        return null
    }
    
    /**
     * Check a file URL (fetch sub-list and check each URL)
     */
    private suspend fun checkFileURL(url: String, customData: String?, recursionDepth: Int): String? {
        Logger.debug("CheckFileURL() called for: $url (depth: $recursionDepth)")
        
        if (url.isEmpty()) {
            lastError = "Empty file URL provided"
            return null
        }
        
        // Fetch sub-list
        Logger.debug("Fetching sub-list from: $url")
        val response = networkClient.get(url)
        
        if (!response.success) {
            lastError = "GET request failed: $url - ${response.error}"
            return null
        }
        
        // Try to parse as JSON first (new format with urls array)
        val subEntries = parseURLEntriesJSON(response.body)
        if (subEntries != null) {
            Logger.debug("Fetched ${subEntries.size} URL entries from JSON sub-list, checking each one...")
            
            // Check each URL entry in sub-list
            for (subEntry in subEntries) {
                Logger.debug("Checking sub-list entry: ${subEntry.url} (method: ${subEntry.method})")
                
                checkURLEntry(subEntry, customData, recursionDepth + 1)?.let { domain ->
                    Logger.info("Sub-list entry succeeded: ${subEntry.url} -> $domain")
                    return domain
                }
                
                Logger.debug("Sub-list entry failed: ${subEntry.url}, trying next...")
                delay(Config.URL_INTERVAL)
            }
        } else {
            // Fallback: parse as plain text URL list (legacy format)
            val subURLs = parseURLList(response.body)
            if (subURLs.isEmpty()) {
                lastError = "Sub-list empty or parse failed: $url"
                return null
            }
            
            Logger.debug("Fetched ${subURLs.size} URLs from text sub-list, checking each one...")
            
            // Check each URL in sub-list (assume API method)
            for (subURL in subURLs) {
                Logger.debug("Checking sub-list URL: $subURL")
                val subEntry = URLEntry(method = "api", url = subURL)
                
                checkURLEntry(subEntry, customData, recursionDepth + 1)?.let { domain ->
                    Logger.info("Sub-list URL succeeded: $subURL -> $domain")
                    return domain
                }
                
                Logger.debug("Sub-list URL failed: $subURL, trying next...")
                delay(Config.URL_INTERVAL)
            }
        }
        
        // All URLs in sub-list failed
        Logger.debug("All URLs in sub-list failed")
        lastError = "All URLs in sub-list failed: $url"
        return null
    }
    
    /**
     * 智能解析 URL entries（支持多种格式）
     * Supports:
     * 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere)
     * 2. HTML with <pre>, <code>, or <script type="application/json"> tags
     * 3. Direct URLEntry[] JSON array format
     * 4. Legacy {"urls": [...]} format
     */
    private fun parseURLEntriesJSON(content: String): List<URLEntry>? {
        Logger.debug("开始智能解析内容（长度: ${content.length}）")

        // Strategy 1: 优先尝试提取 *PGFW* 标记格式
        extractPGFWContent(content)?.let { extracted ->
            Logger.info("✓ 检测到 *PGFW* 标记格式")
            Logger.debug("提取的 base64 长度: ${extracted.length}")

            // Decode base64
            try {
                val decodedBytes = Base64.decode(extracted, Base64.DEFAULT)
                val decodedString = String(decodedBytes, Charsets.UTF_8)
                Logger.debug("解码后的内容: ${decodedString.take(200)}...")

                // Parse as URLEntry[] JSON array
                parseURLEntryArray(decodedString)?.let {
                    Logger.info("✓ 成功从 *PGFW* 标记中解析出 ${it.size} 个 URL entries")
                    return it
                }
            } catch (e: Exception) {
                Logger.debug("Base64 解码失败: ${e.message}")
            }
        }

        // Strategy 2: 检测 HTML 格式
        if (content.contains("<html", ignoreCase = true) ||
            content.contains("<!DOCTYPE", ignoreCase = true)) {
            Logger.info("✓ 检测到 HTML 格式，尝试提取内容...")

            // 2a. 尝试从 <pre> 标签提取
            extractHTMLTag(content, "pre")?.let { preContent ->
                Logger.debug("从 <pre> 标签提取到内容")
                parseURLEntryArray(preContent)?.let {
                    Logger.info("✓ 成功从 <pre> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            // 2b. 尝试从 <code> 标签提取
            extractHTMLTag(content, "code")?.let { codeContent ->
                Logger.debug("从 <code> 标签提取到内容")
                parseURLEntryArray(codeContent)?.let {
                    Logger.info("✓ 成功从 <code> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            // 2c. 尝试从 <script type="application/json"> 提取
            extractJSONScript(content)?.let { scriptContent ->
                Logger.debug("从 <script type=\"application/json\"> 提取到内容")
                parseURLEntryArray(scriptContent)?.let {
                    Logger.info("✓ 成功从 <script> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            Logger.debug("HTML 中未找到可解析的 JSON 内容")
        }

        // Strategy 3: 尝试直接解析为 URLEntry[] JSON 数组
        parseURLEntryArray(content)?.let {
            Logger.info("✓ 成功直接解析为 URLEntry[] 数组（${it.size} 个 entries）")
            return it
        }

        // Strategy 4: 尝试旧版 {"urls": [...]} 格式
        try {
            val gson = Gson()
            val json = gson.fromJson(content, Map::class.java) as? Map<*, *>
            val urlsArray = json?.get("urls") as? List<*>

            urlsArray?.mapNotNull { urlDict ->
                (urlDict as? Map<*, *>)?.let {
                    val method = it["method"] as? String
                    val url = it["url"] as? String
                    val store = it["store"] as? Boolean ?: false
                    if (method != null && url != null) {
                        URLEntry(method, url, store)
                    } else null
                }
            }?.takeIf { it.isNotEmpty() }?.let {
                Logger.info("✓ 成功解析旧版 {\"urls\": [...]} 格式（${it.size} 个 entries）")
                return it
            }
        } catch (e: Exception) {
            Logger.debug("旧版格式解析失败: ${e.message}")
        }

        Logger.warning("所有解析策略均失败")
        return null
    }

    /**
     * 从 HTML 中提取指定标签的内容
     * 支持 HTML 实体解码
     */
    private fun extractHTMLTag(html: String, tag: String): String? {
        try {
            // 匹配 <tag...>content</tag>，支持标签属性
            val pattern = Regex("<$tag[^>]*>(.*?)</$tag>", RegexOption.DOT_MATCHES_ALL or RegexOption.IGNORE_CASE)
            val match = pattern.find(html) ?: return null

            val content = match.groupValues[1]

            // HTML 实体解码
            return decodeHTMLEntities(content)
        } catch (e: Exception) {
            Logger.debug("提取 HTML 标签 <$tag> 失败: ${e.message}")
            return null
        }
    }

    /**
     * 从 HTML 中提取 <script type="application/json"> 的内容
     */
    private fun extractJSONScript(html: String): String? {
        try {
            val pattern = Regex(
                "<script[^>]+type=[\"']application/json[\"'][^>]*>(.*?)</script>",
                RegexOption.DOT_MATCHES_ALL or RegexOption.IGNORE_CASE
            )
            val match = pattern.find(html) ?: return null

            return match.groupValues[1].trim()
        } catch (e: Exception) {
            Logger.debug("提取 JSON script 失败: ${e.message}")
            return null
        }
    }

    /**
     * HTML 实体解码
     */
    private fun decodeHTMLEntities(text: String): String {
        return text
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&")
            .trim()
    }
    
    /**
     * Extract content between *PGFW* markers
     */
    private fun extractPGFWContent(text: String): String? {
        val startMarker = "*PGFW*"
        val endMarker = "*PGFW*"
        
        val startIndex = text.indexOf(startMarker)
        if (startIndex == -1) return null
        
        val contentStart = startIndex + startMarker.length
        val endIndex = text.indexOf(endMarker, contentStart)
        if (endIndex == -1) return null
        
        return text.substring(contentStart, endIndex).trim()
    }
    
    /**
     * Parse URLEntry[] JSON array
     */
    private fun parseURLEntryArray(json: String): List<URLEntry>? {
        return try {
            val gson = Gson()
            val array = gson.fromJson(json, List::class.java) as? List<*>
            
            array?.mapNotNull { item ->
                (item as? Map<*, *>)?.let {
                    val method = it["method"] as? String
                    val url = it["url"] as? String
                    if (method != null && url != null) {
                        URLEntry(method, url)
                    } else null
                }
            }?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Parse URL list from text content
     */
    private fun parseURLList(content: String): List<String> {
        val urls = mutableListOf<String>()
        
        // Try to extract content between *GFW* markers
        val marker = "*GFW*"
        val startIndex = content.indexOf(marker)
        
        if (startIndex != -1) {
            val endIndex = content.indexOf(marker, startIndex + marker.length)
            if (endIndex != -1) {
                val gfwContent = content.substring(startIndex + marker.length, endIndex).trim()
                
                if (gfwContent.isNotEmpty()) {
                    // Parse URLs from marked content
                    gfwContent.lines().forEach { line ->
                        val url = line.trim()
                        if (url.isNotEmpty() && !url.startsWith("#")) {
                            urls.add(url)
                        }
                    }
                    return urls
                }
            }
        }
        
        // If no markers found, parse entire content
        content.lines().forEach { line ->
            val url = line.trim()
            if (url.isNotEmpty() && !url.startsWith("#")) {
                urls.add(url)
            }
        }
        
        return urls
    }
}

