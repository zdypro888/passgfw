package com.passgfw

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PassGFW - Firewall Detection Library (Android)
 * 
 * Main entry point for the PassGFW library.
 */
class PassGFW {
    private val detector = FirewallDetector()
    
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
     */
    fun setURLList(entries: List<URLEntry>) {
        detector.setURLList(entries)
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

