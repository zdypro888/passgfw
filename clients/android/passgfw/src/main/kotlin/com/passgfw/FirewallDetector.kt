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
        
        // Dispatch based on method
        return when (entry.method.lowercase()) {
            "api" -> checkAPIURL(entry.url, customData)
            "file" -> checkFileURL(entry.url, customData, recursionDepth)
            "store" -> {
                // Store this URL to local storage for permanent use
                Logger.info("Storing URL to local storage: ${entry.url}")
                try {
                    val manager = URLStorageManager.getInstance()
                    if (manager.addURL(URLEntry(method = "api", url = entry.url))) {
                        Logger.info("Successfully stored URL: ${entry.url}")
                        // After storing, check it as an API URL
                        checkAPIURL(entry.url, customData)
                    } else {
                        Logger.error("Failed to store URL: ${entry.url}")
                        null
                    }
                } catch (e: Exception) {
                    Logger.error("URLStorageManager not available: ${e.message}")
                    null
                }
            }
            "remove" -> {
                // Remove this URL from local storage
                Logger.info("Removing URL from local storage: ${entry.url}")
                try {
                    val manager = URLStorageManager.getInstance()
                    if (manager.removeURL(entry.url)) {
                        Logger.info("Successfully removed URL: ${entry.url}")
                    } else {
                        Logger.warning("Failed to remove URL (may not exist): ${entry.url}")
                    }
                } catch (e: Exception) {
                    Logger.error("URLStorageManager not available: ${e.message}")
                }
                // Don't check this URL, just skip it
                null
            }
            else -> {
                lastError = "Unknown method: ${entry.method}"
                Logger.error("Unknown method '${entry.method}' for URL: ${entry.url}")
                null
            }
        }
    }
    
    /**
     * Check an API URL with retry mechanism
     */
    private suspend fun checkAPIURL(url: String, customData: String?): String? {
        Logger.debug("CheckAPIURL() called for: $url with customData: $customData")
        
        if (url.isEmpty()) {
            lastError = "Empty URL provided"
            return null
        }
        
        // Retry loop
        for (attempt in 1..Config.MAX_RETRIES) {
            Logger.debug("Attempt $attempt/${Config.MAX_RETRIES} for URL: $url")
            
            checkNormalURLOnce(url, customData)?.let { domain ->
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
    private fun checkNormalURLOnce(url: String, customData: String?): String? {
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
        val returnedDomain = responseJSON?.get("domain") as? String
        val signature = responseJSON?.get("signature") as? String
        
        if (returnedRandom == null || returnedDomain == null || signature == null) {
            lastError = "Response JSON missing required fields (random/domain/signature)"
            return null
        }
        
        Logger.debug("Returned random: $returnedRandom")
        Logger.debug("Returned domain: $returnedDomain")
        
        // 8. Verify signature (sign response without signature field)
        // CRITICAL: Must use sorted keys to match server serialization
        val payloadForSigning = sortedMapOf<String, Any>()
        responseJSON.forEach { (key, value) ->
            if (key != "signature") {
                payloadForSigning[key] = value
            }
        }
        
        val payloadJSON = gson.toJson(payloadForSigning)
        Logger.debug("Payload for verification: $payloadJSON")
        
        val payloadData = payloadJSON.toByteArray(Charsets.UTF_8)
        val signatureData = Base64.decode(signature, Base64.DEFAULT)
        
        if (!cryptoHelper.verifySignature(payloadData, signatureData)) {
            lastError = "Signature verification failed"
            return null
        }
        
        // 10. Verify random matches
        if (returnedRandom != randomBase64) {
            val expectedPrefix = randomBase64.take(10)
            val actualPrefix = returnedRandom.take(10)
            lastError = "Random mismatch: expected: $expectedPrefix..., actual: $actualPrefix..."
            return null
        }
        
        // 11. Success!
        Logger.debug("Verification successful! Using domain: $returnedDomain")
        return returnedDomain
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
     * Parse URL entries from content
     * Supports:
     * 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere)
     * 2. Direct URLEntry[] JSON array format
     * 3. Legacy {"urls": [...]} format
     */
    private fun parseURLEntriesJSON(content: String): List<URLEntry>? {
        // Try to extract *PGFW*base64*PGFW* format first
        extractPGFWContent(content)?.let { extracted ->
            Logger.debug("Found *PGFW* marker, extracted base64 length: ${extracted.length}")
            
            // Decode base64
            try {
                val decodedBytes = Base64.decode(extracted, Base64.DEFAULT)
                val decodedString = String(decodedBytes, Charsets.UTF_8)
                Logger.debug("Decoded PGFW content: ${decodedString.take(200)}...")
                
                // Parse as URLEntry[] JSON array
                parseURLEntryArray(decodedString)?.let { return it }
            } catch (e: Exception) {
                Logger.debug("Failed to decode base64 content: ${e.message}")
            }
        }
        
        // Fallback 1: Try to parse as direct URLEntry[] JSON array
        parseURLEntryArray(content)?.let { return it }
        
        // Fallback 2: Try legacy {"urls": [...]} format
        return try {
            val gson = Gson()
            val json = gson.fromJson(content, Map::class.java) as? Map<*, *>
            val urlsArray = json?.get("urls") as? List<*>
            
            urlsArray?.mapNotNull { urlDict ->
                (urlDict as? Map<*, *>)?.let {
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

