package com.passgfw

import android.util.Base64
import com.google.gson.Gson
import kotlinx.coroutines.delay

/**
 * Firewall Detector - Core detection logic
 */
class FirewallDetector {
    private var urlList: MutableList<String> = Config.getBuiltinURLs().toMutableList()
    private val networkClient = NetworkClient()
    private val cryptoHelper = CryptoHelper()
    private var lastError: String? = null
    
    init {
        // Initialize crypto with public key
        cryptoHelper.setPublicKey(Config.getPublicKey())
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
            
            for (url in urlList) {
                Logger.debug("Checking URL: $url")
                
                checkURL(url, customData, 0)?.let { domain ->
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
    fun setURLList(urls: List<String>) {
        this.urlList = urls.toMutableList()
    }
    
    /**
     * Add URL to list
     */
    fun addURL(url: String) {
        this.urlList.add(url)
    }
    
    /**
     * Get last error
     */
    fun getLastError(): String? = lastError
    
    // MARK: - Private Methods
    
    /**
     * Check a single URL (with recursion support for list#)
     */
    private suspend fun checkURL(url: String, customData: String?, recursionDepth: Int): String? {
        lastError = null
        
        // Check recursion depth limit
        if (recursionDepth > Config.MAX_LIST_RECURSION_DEPTH) {
            lastError = "Maximum list recursion depth exceeded: $url"
            Logger.error("Recursion depth limit reached ($recursionDepth) for URL: $url")
            return null
        }
        
        // Check if it's a list URL (ending with #)
        return if (url.endsWith("#")) {
            checkListURL(url, customData, recursionDepth)
        } else {
            checkNormalURL(url, customData)
        }
    }
    
    /**
     * Check a normal URL with retry mechanism
     */
    private suspend fun checkNormalURL(url: String, customData: String?): String? {
        Logger.debug("CheckNormalURL() called for: $url with customData: $customData")
        
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
        
        val serverResponseJSON = responseJSON?.get("data") as? String
        val signature = responseJSON?.get("signature") as? String
        
        if (serverResponseJSON == null || signature == null) {
            lastError = "Response JSON missing required fields"
            return null
        }
        
        Logger.debug("Server response JSON: $serverResponseJSON")
        
        // 8. Verify signature
        val serverResponseData = serverResponseJSON.toByteArray(Charsets.UTF_8)
        val signatureData = Base64.decode(signature, Base64.DEFAULT)
        
        if (!cryptoHelper.verifySignature(serverResponseData, signatureData)) {
            lastError = "Signature verification failed"
            return null
        }
        
        // 9. Parse server payload
        val serverPayload = try {
            gson.fromJson(serverResponseJSON, Map::class.java) as? Map<*, *>
        } catch (e: Exception) {
            lastError = "Failed to parse server payload: ${e.message}"
            return null
        }
        
        val returnedNonce = serverPayload?.get("nonce") as? String
        val returnedDomain = serverPayload?.get("server_domain") as? String
        
        if (returnedNonce == null || returnedDomain == null) {
            lastError = "Server payload missing required fields"
            return null
        }
        
        Logger.debug("Returned nonce: $returnedNonce")
        Logger.debug("Returned domain: $returnedDomain")
        
        // 10. Verify nonce matches
        if (returnedNonce != randomBase64) {
            val expectedPrefix = randomBase64.take(10)
            val actualPrefix = returnedNonce.take(10)
            lastError = "Nonce mismatch: expected: $expectedPrefix..., actual: $actualPrefix..."
            return null
        }
        
        // 11. Success!
        Logger.debug("Verification successful! Using domain: $returnedDomain")
        return returnedDomain
    }
    
    /**
     * Check a list URL (fetch sub-list and check each URL)
     */
    private suspend fun checkListURL(url: String, customData: String?, recursionDepth: Int): String? {
        Logger.debug("CheckListURL() called for: $url (depth: $recursionDepth)")
        
        if (url.length < 2) {
            lastError = "Invalid list URL: too short"
            return null
        }
        
        // Remove trailing #
        val actualURL = url.dropLast(1)
        if (actualURL.isEmpty()) {
            lastError = "Empty URL after removing #"
            return null
        }
        
        // Fetch sub-list
        Logger.debug("Fetching sub-list from: $actualURL")
        val response = networkClient.get(actualURL)
        
        if (!response.success) {
            lastError = "GET request failed: $actualURL - ${response.error}"
            return null
        }
        
        // Parse URL list
        val subURLs = parseURLList(response.body)
        if (subURLs.isEmpty()) {
            lastError = "Sub-list empty or parse failed: $actualURL"
            return null
        }
        
        Logger.debug("Fetched ${subURLs.size} URLs from sub-list, checking each one...")
        
        // Check each URL in sub-list
        for (subURL in subURLs) {
            Logger.debug("Checking sub-list URL: $subURL")
            
            checkURL(subURL, customData, recursionDepth + 1)?.let { domain ->
                Logger.info("Sub-list URL succeeded: $subURL -> $domain")
                return domain
            }
            
            Logger.debug("Sub-list URL failed: $subURL, trying next...")
            delay(Config.URL_INTERVAL)
        }
        
        // All URLs in sub-list failed
        Logger.debug("All URLs in sub-list failed")
        lastError = "All URLs in sub-list failed: $actualURL"
        return null
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

