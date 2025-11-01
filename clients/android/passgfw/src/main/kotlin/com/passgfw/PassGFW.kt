package com.passgfw

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PassGFW - Firewall Detection Library (Android)
 *
 * Main entry point for the PassGFW library.
 */
class PassGFW(context: Context) {
    private val detector = FirewallDetector(context)
    
    /**
     * Get the final available server domain
     * @param customData Optional custom data to send with requests
     * @return The final server domain, or null if all attempts fail
     */
    suspend fun getFinalServer(customData: String? = null): String? = withContext(Dispatchers.IO) {
        detector.getFinalServer(customData)
    }
    
    /**
     * Set the URL list to check
     * @param entries List of URL entries to check
     *
     * 注意：此方法已废弃，建议使用 addURL 方法逐个添加
     * URLs 将被持久化到存储中
     */
    @Deprecated("Use addURL instead for better control", ReplaceWith("entries.forEach { addURL(it.method, it.url) }"))
    fun setURLList(entries: List<URLEntry>) {
        // 批量添加 URL 到存储（异步操作）
        entries.forEach { entry ->
            detector.addURL(entry.method, entry.url)
        }
    }
    
    /**
     * Add a URL entry to the check list
     * @param method Method type ("api" or "file")
     * @param url URL to add
     */
    fun addURL(method: String, url: String) {
        detector.addURL(method, url)
    }
    
    /**
     * Get the last error message
     * @return Last error message, or null if no error
     */
    fun getLastError(): String? {
        return detector.getLastError()
    }
    
    /**
     * Enable or disable logging
     * @param enabled Whether to enable logging
     */
    fun setLoggingEnabled(enabled: Boolean) {
        Logger.isEnabled = enabled
    }
    
    /**
     * Set the minimum log level
     * @param level Minimum log level to display
     */
    fun setLogLevel(level: LogLevel) {
        Logger.minLevel = level
    }
}

