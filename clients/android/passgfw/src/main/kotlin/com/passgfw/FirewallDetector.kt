package com.passgfw

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

/**
 * Firewall Detector - Core detection logic
 */
class FirewallDetector(private val context: Context) {
    private val networkClient = NetworkClient()
    private val cryptoHelper = CryptoHelper()
    private val urlManager: URLManager

    // 缓存最后成功的结果
    private var cachedResult: Map<String, Any>? = null
    private var lastError: String? = null

    init {
        // Set public key
        val publicKey = Config.getPublicKey()
        if (!cryptoHelper.setPublicKey(publicKey)) {
            Logger.error("Failed to set public key")
        }

        // Initialize URL Manager
        urlManager = URLManager(context)
        if (urlManager.initializeIfNeeded()) {
            Logger.info("URLManager initialized")
        } else {
            Logger.warning("URLManager initialization failed")
        }
    }

    /**
     * Get domains by checking URL list
     * @param retry If true, force re-detection. If false, return cache if available.
     * @param customData Optional custom data to send with requests
     * @return Map containing server response data, or null if all attempts fail
     */
    suspend fun getDomains(retry: Boolean, customData: String?): Map<String, Any>? {
        // If not retry and cache exists, return cache
        if (!retry && cachedResult != null) {
            Logger.info("Returning cached result")
            return cachedResult
        }

        // Perform detection
        Logger.info("Starting detection (retry=$retry)")

        // Infinite retry loop until success
        while (true) {
            val urls = urlManager.getURLs()
            Logger.debug("Checking ${urls.size} URLs")

            val result = checkURLsSequentially(urls, customData, 0)
            if (result != null) {
                // Success - cache and return
                cachedResult = result
                Logger.info("Detection succeeded")
                return result
            }

            // All failed, wait and retry
            lastError = "All URLs failed, retrying..."
            Logger.warning(lastError!!)
            delay(Config.RETRY_INTERVAL)
        }
    }

    /**
     * Get last error
     */
    fun getLastError(): String? = lastError

    // MARK: - Private Methods

    /**
     * Check URLs sequentially
     */
    private suspend fun checkURLsSequentially(
        entries: List<URLEntry>,
        customData: String?,
        recursionDepth: Int
    ): Map<String, Any>? {
        for (entry in entries) {
            Logger.debug("Checking URL: ${entry.url} (method: ${entry.method}, depth: $recursionDepth)")

            val result = checkURLEntry(entry, customData, recursionDepth)
            if (result != null) {
                Logger.info("Found available server")
                return result
            }

            // Small delay between checks
            delay(Config.URL_INTERVAL)
        }
        return null
    }

    /**
     * Check single URL entry
     */
    private suspend fun checkURLEntry(
        entry: URLEntry,
        customData: String?,
        recursionDepth: Int
    ): Map<String, Any>? {
        return when (entry.method) {
            "api" -> checkAPIMethod(entry, customData)
            "file" -> checkFileMethod(entry, customData, recursionDepth)
            "navigate" -> {
                handleNavigateMethod(entry)
                // Navigate 执行后算成功，返回表示已引导用户
                mapOf("navigated" to true, "url" to entry.url)
            }
            "remove" -> {
                handleRemoveMethod(entry)
                // Remove 执行后继续下一个（返回null）
                null
            }
            else -> {
                Logger.warning("Unknown method: ${entry.method}")
                null
            }
        }
    }

    /**
     * Check API method
     */
    private suspend fun checkAPIMethod(entry: URLEntry, customData: String?): Map<String, Any>? {
        // Generate random nonce
        val nonceData = cryptoHelper.generateRandom(Config.NONCE_SIZE)
        val randomBase64 = Base64.encodeToString(nonceData, Base64.NO_WRAP)

        // Prepare client data
        val clientData = JSONObject().apply {
            put("domain", "example.com")
        }

        // Build request payload
        val payload = JSONObject().apply {
            put("nonce", randomBase64)
            put("os", "android")
            put("app", context.packageName)
            put("data", customData ?: clientData.toString())
        }

        val payloadBytes = payload.toString().toByteArray()

        // Encrypt payload
        val encryptedData = cryptoHelper.encrypt(payloadBytes)
        if (encryptedData == null) {
            Logger.error("Failed to encrypt payload")
            return null
        }

        // Send request
        val response = networkClient.postBytes(entry.url, encryptedData)

        if (!response.success) {
            Logger.warning("API request failed: ${response.error}")
            return null
        }

        // Parse response
        val responseJSON = try {
            JSONObject(response.body)
        } catch (e: Exception) {
            Logger.error("Failed to parse response JSON: ${e.message}")
            return null
        }

        // Get nonce, data, signature (all base64 strings in JSON)
        val returnedNonceBase64 = responseJSON.optString("nonce")
        val dataBase64 = responseJSON.optString("data")
        val signatureBase64 = responseJSON.optString("signature")

        if (returnedNonceBase64.isEmpty() || dataBase64.isEmpty() || signatureBase64.isEmpty()) {
            Logger.error("Missing required fields")
            return null
        }

        // Verify nonce (decode and compare bytes)
        val returnedNonceData = Base64.decode(returnedNonceBase64, Base64.DEFAULT)
        if (!nonceData.contentEquals(returnedNonceData)) {
            Logger.error("Nonce mismatch")
            return null
        }

        // Decode data and signature
        val dataBytes = Base64.decode(dataBase64, Base64.DEFAULT)
        val signatureData = Base64.decode(signatureBase64, Base64.DEFAULT)

        // Rebuild response for verification (same structure as server)
        // IMPORTANT: Keep base64 strings, don't decode to []byte
        val responseForVerify = JSONObject()
        responseForVerify.put("nonce", returnedNonceBase64)
        responseForVerify.put("data", dataBase64)

        // Add URLs if present
        if (responseJSON.has("urls")) {
            responseForVerify.put("urls", responseJSON.getJSONArray("urls"))
        }

        // Serialize to bytes (JSONObject maintains field insertion order)
        val verifyBytes = responseForVerify.toString().toByteArray()

        // Verify signature
        if (!cryptoHelper.verifySignature(verifyBytes, signatureData)) {
            Logger.error("Signature verification failed")
            return null
        }

        Logger.info("API check succeeded for ${entry.url}")

        // Parse data JSON
        val parsedData = try {
            val dataString = String(dataBytes)
            val dataObj = JSONObject(dataString)
            jsonObjectToMap(dataObj)
        } catch (e: Exception) {
            Logger.error("Failed to parse data JSON: ${e.message}")
            return null
        }

        // Handle store flag
        if (entry.store) {
            urlManager.addURL(entry)
            Logger.debug("Store URL ${entry.url}")
        }

        // Handle dynamic URLs from response
        if (responseJSON.has("urls")) {
            handleDynamicURLs(responseJSON.getJSONArray("urls"))
        }

        // Return parsed data
        return parsedData
    }

    /**
     * Check file method
     */
    private suspend fun checkFileMethod(
        entry: URLEntry,
        customData: String?,
        recursionDepth: Int
    ): Map<String, Any>? {
        // Check recursion depth
        if (recursionDepth >= Config.MAX_LIST_RECURSION_DEPTH) {
            Logger.warning("Max recursion depth reached")
            return null
        }

        // Fetch file
        val response = networkClient.get(entry.url)

        if (!response.success) {
            Logger.warning("File request failed: ${response.error}")
            return null
        }

        // Parse URL list
        val urls = parseURLList(response.body)
        if (urls == null) {
            Logger.error("Failed to parse URL list")
            return null
        }

        Logger.info("File method: loaded ${urls.size} URLs from ${entry.url}")

        // Handle store flag
        if (entry.store) {
            urlManager.addURL(entry)
            Logger.debug("Store file URL ${entry.url}")
        }

        // Check nested URLs
        return checkURLsSequentially(urls, customData, recursionDepth + 1)
    }

    /**
     * Handle navigate method
     */
    private fun handleNavigateMethod(entry: URLEntry) {
        Logger.info("Navigate method: opening ${entry.url}")
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(entry.url))
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        } catch (e: Exception) {
            Logger.error("Failed to open URL: ${e.message}")
        }
    }

    /**
     * Handle remove method
     */
    private fun handleRemoveMethod(entry: URLEntry) {
        Logger.info("Remove method: removing ${entry.url}")
        urlManager.removeURL(entry.url)
        Logger.debug("Remove URL ${entry.url}")
    }

    /**
     * Handle dynamic URLs from API response
     */
    private fun handleDynamicURLs(urlsJSON: JSONArray) {
        for (i in 0 until urlsJSON.length()) {
            val urlObj = urlsJSON.getJSONObject(i)
            val method = urlObj.optString("method")
            val url = urlObj.optString("url")

            if (method.isEmpty() || url.isEmpty()) continue

            val store = urlObj.optBoolean("store", false)
            val entry = URLEntry(method, url, store)

            when (method) {
                "remove" -> {
                    urlManager.removeURL(url)
                    Logger.debug("Dynamic remove: $url")
                }
                "api", "file" -> {
                    if (store) {
                        urlManager.addURL(entry)
                        Logger.debug("Dynamic store: $url")
                    }
                }
                "navigate" -> handleNavigateMethod(entry)
                else -> Logger.warning("Unknown dynamic method: $method")
            }
        }
    }

    /**
     * Parse URL list from text
     */
    private fun parseURLList(text: String): List<URLEntry>? {
        // Try *PGFW* format first
        extractPGFWContent(text)?.let { pgfwContent ->
            try {
                val jsonArray = JSONArray(pgfwContent)
                return parseURLEntriesFromJSON(jsonArray)
            } catch (e: Exception) {
                // Continue to next format
            }
        }

        // Try direct JSON array
        try {
            val jsonArray = JSONArray(text)
            return parseURLEntriesFromJSON(jsonArray)
        } catch (e: Exception) {
            // Continue to next format
        }

        // Try legacy format {"urls": [...]}
        try {
            val json = JSONObject(text)
            if (json.has("urls")) {
                val urlsArray = json.getJSONArray("urls")
                return parseURLEntriesFromJSON(urlsArray)
            }
        } catch (e: Exception) {
            // Continue to next format
        }

        // Fallback: plain text (one URL per line)
        val entries = mutableListOf<URLEntry>()
        for (line in text.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
            if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
                entries.add(URLEntry("api", trimmed, false))
            }
        }

        return if (entries.isEmpty()) null else entries
    }

    /**
     * Extract content from *PGFW*...*PGFW* markers
     */
    private fun extractPGFWContent(text: String): String? {
        val startMarker = "*PGFW*"
        val endMarker = "*PGFW*"

        val startIndex = text.indexOf(startMarker)
        if (startIndex == -1) return null

        val contentStart = startIndex + startMarker.length
        val endIndex = text.indexOf(endMarker, contentStart)
        if (endIndex == -1) return null

        val base64String = text.substring(contentStart, endIndex)
        return try {
            val decodedBytes = Base64.decode(base64String, Base64.DEFAULT)
            String(decodedBytes)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Parse URL entries from JSON array
     */
    private fun parseURLEntriesFromJSON(jsonArray: JSONArray): List<URLEntry> {
        val entries = mutableListOf<URLEntry>()
        for (i in 0 until jsonArray.length()) {
            val obj = jsonArray.getJSONObject(i)
            val method = obj.optString("method")
            val url = obj.optString("url")
            if (method.isNotEmpty() && url.isNotEmpty()) {
                val store = obj.optBoolean("store", false)
                entries.add(URLEntry(method, url, store))
            }
        }
        return entries
    }

    /**
     * Convert JSONObject to Map
     */
    private fun jsonObjectToMap(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    /**
     * Convert JSONArray to List
     */
    private fun jsonArrayToList(json: JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until json.length()) {
            val value = json.get(i)
            list.add(when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            })
        }
        return list
    }
}
